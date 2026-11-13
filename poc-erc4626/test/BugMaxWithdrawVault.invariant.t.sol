// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugMaxWithdrawVault} from "../src/BugMaxWithdrawVault.sol";

/// Catalog validation, BUG 3 — max* desync / withdrawal DoS.
/// Target invariant — I5 (invariant_I5_maxWithdrawHonored): withdraw(maxWithdraw(a)) reverts,
/// because maxWithdraw promises the full share value, but withdraw imposes a per-tx cap WITHDRAW_CAP.
/// On NaiveVault (no cap) I5 holds — the control.
contract BugMaxWithdrawVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugMaxWithdrawVault(asset_)));
    }
}
