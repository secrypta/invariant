// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {OZVault} from "../src/OZVault.sol";
import {NaiveVault} from "../src/NaiveVault.sol";
import {BugPreviewDepositLiesVault} from "../src/BugPreviewDepositLiesVault.sol";
import {BugPreviewRedeemLiesVault} from "../src/BugPreviewRedeemLiesVault.sol";
import {BugMaxRedeemLiesVault} from "../src/BugMaxRedeemLiesVault.sol";
import {BugRedeemCapVault} from "../src/BugRedeemCapVault.sol";
import {BugSolvencyMintVault} from "../src/BugSolvencyMintVault.sol";
import {BugSolvencyBurnVault} from "../src/BugSolvencyBurnVault.sol";

/// @title Extra-mechanism — deterministic repros of the SECOND/THIRD mechanisms per invariant (ERC-4626). Independent of the fuzzer.
/// Each: the target property is violated on the vulnerable target, holds on the correct one (OZ offset=3 / honest baseline).
contract ValidationReprosExtra is Test {
    MockERC20 internal token;
    address internal constant LP = address(0xB0B);
    address internal constant ATK = address(0xA11CE);

    function setUp() public {
        token = new MockERC20();
    }

    function _fund(address a, uint256 amt, address vault) internal {
        token.mint(a, amt);
        vm.prank(a);
        token.approve(vault, type(uint256).max);
    }

    // ===== I6 (2nd) — BugPreviewDepositLies: previewDeposit (ceil) lies vs actual issuance (floor) =====
    function test_I6_depositLies_previewOverstates() public {
        BugPreviewDepositLiesVault v = new BugPreviewDepositLiesVault(token);
        // create a share price != 1: deposit 1000, then donate 500 -> ta=1500, ts=1000
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        v.deposit(1000, LP);
        token.mint(address(v), 500);
        uint256 amt = 1000;
        uint256 quote = v.previewDeposit(amt);
        _fund(ATK, amt, address(v));
        vm.prank(ATK);
        uint256 got = v.deposit(amt, ATK);
        console2.log("I6 DepositLies: previewDeposit / fakt doli:", quote, got);
        assertGt(quote, got, "I6: previewDeposit ne zavysil (ne ozhidali)");
    }

    function test_I6_depositLies_control_oz() public {
        OZVault v = new OZVault(token, 3);
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        v.deposit(1000, LP);
        token.mint(address(v), 500);
        uint256 amt = 1000;
        uint256 quote = v.previewDeposit(amt);
        _fund(ATK, amt, address(v));
        vm.prank(ATK);
        uint256 got = v.deposit(amt, ATK);
        assertLe(quote, got, "I6 control: previewDeposit zavysil na OZ(3)");
    }

    // ===== I6 (3rd) — BugPreviewRedeemLies: previewRedeem (x1.01) lies vs actual payout =====
    function test_I6_redeemLies_previewOverstates() public {
        BugPreviewRedeemLiesVault v = new BugPreviewRedeemLiesVault(token);
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        uint256 sh = v.deposit(1000, LP);
        uint256 quote = v.previewRedeem(sh);
        uint256 bal0 = token.balanceOf(LP);
        vm.prank(LP);
        v.redeem(sh, LP, LP);
        uint256 got = token.balanceOf(LP) - bal0;
        console2.log("I6 RedeemLies: previewRedeem / fakt vyplata:", quote, got);
        assertGt(quote, got + 1, "I6: previewRedeem ne zavysil (ne ozhidali)");
    }

    function test_I6_redeemLies_control_oz() public {
        OZVault v = new OZVault(token, 3);
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        uint256 sh = v.deposit(1000, LP);
        uint256 quote = v.previewRedeem(sh);
        uint256 bal0 = token.balanceOf(LP);
        vm.prank(LP);
        v.redeem(sh, LP, LP);
        uint256 got = token.balanceOf(LP) - bal0;
        assertLe(quote, got + 1, "I6 control: previewRedeem zavysil na OZ(3)");
    }

    // ===== I5 (2nd) — BugMaxRedeemLies: redeem(maxRedeem) reverts =====
    function test_I5_maxRedeemLies_reverts() public {
        BugMaxRedeemLiesVault v = new BugMaxRedeemLiesVault(token);
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        v.deposit(1000, LP);
        uint256 mr = v.maxRedeem(LP);
        vm.prank(LP);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.redeem.selector, mr, LP, LP));
        console2.log("I5 MaxRedeemLies: maxRedeem / balance:", mr, v.balanceOf(LP));
        assertFalse(ok, "I5b: redeem(maxRedeem) ne revertnul (ne ozhidali)");
    }

    function test_I5_maxRedeemLies_control_oz() public {
        OZVault v = new OZVault(token, 3);
        _fund(LP, 1000, address(v));
        vm.prank(LP);
        v.deposit(1000, LP);
        uint256 mr = v.maxRedeem(LP);
        vm.prank(LP);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.redeem.selector, mr, LP, LP));
        assertTrue(ok, "I5b control: redeem(maxRedeem) revert na OZ(3)");
    }

    // ===== I5 (3rd) — BugRedeemCap: redeem(maxRedeem) reverts due to a per-tx cap =====
    function test_I5_redeemCap_reverts() public {
        BugRedeemCapVault v = new BugRedeemCapVault(token);
        uint256 big = 2e21; // > REDEEM_CAP=1e21
        _fund(LP, big, address(v));
        vm.prank(LP);
        v.deposit(big, LP);
        uint256 mr = v.maxRedeem(LP);
        vm.prank(LP);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.redeem.selector, mr, LP, LP));
        console2.log("I5 RedeemCap: maxRedeem:", mr);
        assertFalse(ok, "I5b: redeem(maxRedeem) ne revertnul pri cap (ne ozhidali)");
    }

    function test_I5_redeemCap_control_oz() public {
        OZVault v = new OZVault(token, 3);
        uint256 big = 2e21;
        _fund(LP, big, address(v));
        vm.prank(LP);
        v.deposit(big, LP);
        uint256 mr = v.maxRedeem(LP);
        vm.prank(LP);
        (bool ok,) = address(v).call(abi.encodeWithSelector(v.redeem.selector, mr, LP, LP));
        assertTrue(ok, "I5b control: redeem(maxRedeem) revert na OZ(3)");
    }

    // ===== I3 (2nd) — BugSolvencyMint: mint prints an unbacked share =====
    function test_I3_solvencyMint_overIssue() public {
        BugSolvencyMintVault v = new BugSolvencyMintVault(token);
        _fund(ATK, 1000, address(v));
        vm.prank(ATK);
        v.mint(1000, ATK); // pulls 1000 assets, mints 1001 shares
        uint256 redeemable = v.previewRedeem(v.balanceOf(ATK));
        console2.log("I3 SolvencyMint: redeemable / totalAssets:", redeemable, v.totalAssets());
        assertGt(redeemable, v.totalAssets(), "I3: emissiya obespechena (ne ozhidali)");
    }

    function test_I3_solvencyMint_control_naive() public {
        NaiveVault v = new NaiveVault(token);
        _fund(ATK, 1000, address(v));
        vm.prank(ATK);
        v.mint(1000, ATK);
        assertLe(v.previewRedeem(v.balanceOf(ATK)), v.totalAssets(), "I3 control: neplatezhesposobnost na Naive");
    }

    // ===== I3 (3rd) — BugSolvencyBurn: withdrawal leaves a phantom share =====
    function test_I3_solvencyBurn_phantomShare() public {
        BugSolvencyBurnVault v = new BugSolvencyBurnVault(token);
        _fund(ATK, 1000, address(v));
        vm.prank(ATK);
        v.deposit(1000, ATK);
        vm.prank(ATK);
        v.redeem(400, ATK, ATK); // burns 399, returns 400 assets -> phantom share
        uint256 redeemable = v.previewRedeem(v.balanceOf(ATK));
        console2.log("I3 SolvencyBurn: redeemable / totalAssets:", redeemable, v.totalAssets());
        assertGt(redeemable, v.totalAssets(), "I3: net fantomnoj doli (ne ozhidali)");
    }

    function test_I3_solvencyBurn_control_naive() public {
        NaiveVault v = new NaiveVault(token);
        _fund(ATK, 1000, address(v));
        vm.prank(ATK);
        v.deposit(1000, ATK);
        vm.prank(ATK);
        v.redeem(400, ATK, ATK);
        assertLe(v.previewRedeem(v.balanceOf(ATK)), v.totalAssets(), "I3 control: fantom na Naive");
    }
}
