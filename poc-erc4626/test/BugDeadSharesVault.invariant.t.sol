// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugDeadSharesVault} from "../src/BugDeadSharesVault.sol";

/// Catalog validation, BUG 4 - weak dead-shares protection (an I2 gate backstop).
/// Target invariant - I2 (attacker-no-profit): the fixed DEAD_SHARES do not scale,
/// a large attacker deposit + donation break through the protection → profit > SLACK. The same I2 holds on
/// OZVault(offset=3) - so I2 catches the CLASS "attacker profit", not a specific implementation.
contract BugDeadSharesVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugDeadSharesVault(asset_)));
    }
}
