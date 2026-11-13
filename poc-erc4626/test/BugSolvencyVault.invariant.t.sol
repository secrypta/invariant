// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugSolvencyVault} from "../src/BugSolvencyVault.sol";

/// Catalog validation, BUG 2 — over-issuance / solvency hole.
/// Target invariant — I3 (solvency, strict assertLe without tolerance): the sum of redeemable across holders
/// exceeds totalAssets already after the first deposit (an unbacked share was issued).
/// I2/I7 with a SLACK=256 tolerance let the "dust" +1 wei/op through — this shows why the strict I3 is needed separately.
contract BugSolvencyVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugSolvencyVault(asset_)));
    }
}
