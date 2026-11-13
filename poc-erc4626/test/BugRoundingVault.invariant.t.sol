// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugRoundingVault} from "../src/BugRoundingVault.sol";

/// Catalog validation, BUG 1 — rounding-direction (rounding in the user's favor).
/// Target invariant — I6 (rounding DIRECTION). The leak is ≤1 ulp/op (< SLACK=256), so
/// the I2 profit threshold and the I7 round-trip threshold do NOT catch it (SLACK absorbs the dust) — the direction probe catches it:
/// previewRedeem(previewDeposit(a)) must be ≤ a; on this target, when the share price ≠ 1, it becomes > a.
contract BugRoundingVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugRoundingVault(asset_)));
    }

    /// I6-direction (the operational form of I6): a round-trip preview deposit→redeem must not return more.
    /// For a correct vault (Naive/OZ) it is always ≤ a (floor·floor). Here (ceil·ceil) with ts≠ta it gives > a.
    function invariant_I6dir_previewRoundTripNoProfit() public view {
        uint256[4] memory amts = [uint256(1), 1e3, 1e9, 1e18];
        for (uint256 i; i < amts.length; ++i) {
            uint256 a = amts[i];
            uint256 back = vault.previewRedeem(vault.previewDeposit(a));
            assertLe(back, a, "I6-dir: preview round-trip vernul > deposit (okruglenie v polzu usera)");
        }
    }
}
