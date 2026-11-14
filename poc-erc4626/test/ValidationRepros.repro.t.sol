// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {NaiveVault} from "../src/NaiveVault.sol";
import {OZVault} from "../src/OZVault.sol";
import {BugRoundingVault} from "../src/BugRoundingVault.sol";
import {BugSolvencyVault} from "../src/BugSolvencyVault.sol";
import {BugMaxWithdrawVault} from "../src/BugMaxWithdrawVault.sol";
import {BugDeadSharesVault} from "../src/BugDeadSharesVault.sol";
import {BugMinDepositVault} from "../src/BugMinDepositVault.sol";

/// @title Deterministic repros for catalog validation. Independent of the fuzzer/shrinker.
/// Each bug class: on the vulnerable target the target property is violated, on the correct one (OZ offset=3 / Naive) it holds.
contract ValidationRepros is Test {
    MockERC20 internal token;
    address internal constant A = address(0xA11CE); // attacker / userA
    address internal constant B = address(0xB0B);   // victim / userB

    function setUp() public {
        token = new MockERC20();
    }

    function _fund(address who, uint256 amt, address v) internal {
        token.mint(who, amt);
        vm.prank(who);
        token.approve(v, type(uint256).max);
    }

    // ===================== BUG 1 - rounding-direction (target I6) =====================
    /// A round-trip deposit→redeem when the share price ≠ 1: on BugRounding it returns MORE than deposited.
    function _roundingRoundTrip(IVault v) internal returns (uint256 deposited, uint256 got) {
        _fund(A, 1000, address(v));
        vm.prank(A);
        v.deposit(1000, A); // ts=1000, ta=1000
        // simulate yield/price ≠ 1: a direct transfer of 500 assets to the vault
        token.mint(address(this), 500);
        token.transfer(address(v), 500); // ta=1500, ts=1000 → price=1.5
        // a round-trip by a second user
        _fund(B, 1000, address(v));
        vm.prank(B);
        uint256 sh = v.deposit(1000, B);
        vm.prank(B);
        got = v.redeem(sh, B, B);
        deposited = 1000;
    }

    function test_bug1_rounding_extracts() public {
        BugRoundingVault v = new BugRoundingVault(token);
        (uint256 dep, uint256 got) = _roundingRoundTrip(IVault(address(v)));
        console2.log("BUG1 BugRounding: deposited / got-back:", dep, got);
        assertGt(got, dep, "BUG1: round-trip NE izvlek (ozhidali got > deposited)");
    }

    function test_bug1_control_oz3_safe() public {
        OZVault v = new OZVault(token, 3);
        (uint256 dep, uint256 got) = _roundingRoundTrip(IVault(address(v)));
        console2.log("BUG1 OZ(3) control: deposited / got-back:", dep, got);
        assertLe(got, dep, "BUG1 control: round-trip izvlek na korrektnom vault");
    }

    // ===================== BUG 2 - over-issuance (target I3) =====================
    function _sumRedeemableVsAssets(IVault v) internal returns (uint256 sumRedeemable, uint256 ta) {
        _fund(A, 1000, address(v));
        vm.prank(A);
        v.deposit(1000, A);
        sumRedeemable = v.previewRedeem(v.balanceOf(A));
        ta = v.totalAssets();
    }

    function test_bug2_solvency_insolvent() public {
        BugSolvencyVault v = new BugSolvencyVault(token);
        (uint256 red, uint256 ta) = _sumRedeemableVsAssets(IVault(address(v)));
        console2.log("BUG2 BugSolvency: sum redeemable / totalAssets:", red, ta);
        assertGt(red, ta, "BUG2: ozhidali sum redeemable > totalAssets");
    }

    function test_bug2_control_naive_solvent() public {
        NaiveVault v = new NaiveVault(token);
        (uint256 red, uint256 ta) = _sumRedeemableVsAssets(IVault(address(v)));
        console2.log("BUG2 Naive control: sum redeemable / totalAssets:", red, ta);
        assertLe(red, ta, "BUG2 control: naive neplatezhesposoben (ne ozhidali)");
    }

    // ===================== BUG 3 - max* desync / DoS (target I5) =====================
    function test_bug3_maxWithdraw_reverts() public {
        BugMaxWithdrawVault v = new BugMaxWithdrawVault(token);
        uint256 amt = 2e21; // > WITHDRAW_CAP (1e21)
        _fund(A, amt, address(v));
        vm.prank(A);
        v.deposit(amt, A);
        uint256 mw = v.maxWithdraw(A);
        console2.log("BUG3 BugMaxWithdraw: maxWithdraw / cap:", mw, v.WITHDRAW_CAP());
        vm.prank(A);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.withdraw.selector, mw, A, A));
        assertFalse(ok, "BUG3: withdraw(maxWithdraw) NE revertnul (ozhidali revert)");
    }

    function test_bug3_control_naive_honored() public {
        NaiveVault v = new NaiveVault(token);
        uint256 amt = 2e21;
        _fund(A, amt, address(v));
        vm.prank(A);
        v.deposit(amt, A);
        uint256 mw = v.maxWithdraw(A);
        vm.prank(A);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.withdraw.selector, mw, A, A));
        assertTrue(ok, "BUG3 control: withdraw(maxWithdraw) revertnul na naive (ne ozhidali)");
    }

    // ===================== donation inflation: attacker profit (gate I2) =====================
    /// Scenario: attacker deposit(D) → donate(DON) → victim deposit(VIC) → attacker redeem all.
    function _donationAttack(IVault v, uint256 D, uint256 DON, uint256 VIC)
        internal
        returns (int256 attackerProfit)
    {
        _fund(A, D, address(v));
        vm.prank(A);
        v.deposit(D, A);

        token.mint(A, DON);
        vm.prank(A);
        token.transfer(address(v), DON); // direct donation

        _fund(B, VIC, address(v));
        vm.prank(B);
        v.deposit(VIC, B);

        uint256 sh = v.balanceOf(A);
        if (sh > 0) {
            vm.prank(A);
            v.redeem(sh, A, A);
        }
        uint256 fundedA = D + DON;
        attackerProfit = int256(token.balanceOf(A)) - int256(fundedA);
    }

    // BUG 5 - security theater (min-deposit): the 2nd FAILING I2 target via a different mechanism.
    function test_bug5_minDeposit_profitable() public {
        BugMinDepositVault v = new BugMinDepositVault(token);
        // attack depth: attacker/victim >= MIN_DEPOSIT (1e6); large donation
        int256 p = _donationAttack(IVault(address(v)), 1e6, 1e24, 1e6);
        console2.log("BUG5 BugMinDeposit attacker profit (assets):");
        console2.logInt(p);
        assertGt(p, int256(256), "BUG5: ataka ne pribylna (zashchita-teatr dolzhna probivatsya)");
    }

    function test_bug5_control_oz3_safe() public {
        OZVault v = new OZVault(token, 3);
        int256 p = _donationAttack(IVault(address(v)), 1e6, 1e24, 1e6);
        console2.log("BUG5 OZ(3) control attacker profit (assets):");
        console2.logInt(p);
        assertLe(p, int256(256), "BUG5 control: ataka pribylna na OZ(3) (fix sloman)");
    }

    // BUG 4 - dead-shares: a SOUND protection. The same attack is profitable on Naive but LOSS-MAKING here → I2 is SILENT.
    function test_bug4_deadShares_defends() public {
        BugDeadSharesVault v = new BugDeadSharesVault(token);
        int256 p = _donationAttack(IVault(address(v)), 1, 1e21, 1e21); // classic: attacker 1 wei
        console2.log("BUG4 BugDeadShares attacker profit (assets):");
        console2.logInt(p);
        assertLe(p, int256(256), "BUG4: dead-shares NE zashchitili (ozhidali ubytok atakuyushchego)");
    }

    /// Counterexample: the SAME attack on NaiveVault is profitable → so it is the dead-shares that protect, not the scenario.
    function test_bug4_contrast_naive_profitable() public {
        NaiveVault v = new NaiveVault(token);
        int256 p = _donationAttack(IVault(address(v)), 1, 1e21, 1e21);
        console2.log("BUG4 contrast Naive attacker profit (assets):");
        console2.logInt(p);
        assertGt(p, int256(256), "BUG4 contrast: ataka ne probila golyj naive (neozhidanno)");
    }
}
