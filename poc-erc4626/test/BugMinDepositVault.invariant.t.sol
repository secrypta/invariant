// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugMinDepositVault} from "../src/BugMinDepositVault.sol";

/// Catalog validation, BUG 5 — security theater (min-deposit), the 2nd FAILING I2 target via a different mechanism.
/// Target invariant — I2 (attacker-no-profit): min-deposit does not fix the share math, donation inflation
/// goes through → attacker profit > SLACK. The same I2 holds on OZVault(offset=3). Confirms that I2
/// catches the CLASS, not the implementation: it fails on NaiveVault (no protection) and here (protection misses the point).
contract BugMinDepositVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugMinDepositVault(asset_)));
    }
}
