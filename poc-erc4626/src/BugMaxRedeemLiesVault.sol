// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NaiveVault} from "./NaiveVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BugMaxRedeemLiesVault — 2nd I5 mechanism (max* desync, redeem branch).
/// @notice The math is correct (NaiveVault), BUT `maxRedeem` LIES: it returns more than the owner holds.
/// An integrator calling redeem(maxRedeem(a)) gets a revert (burning more than the balance). Differs from
/// BugMaxWithdrawVault (a per-tx cap there with a correct maxWithdraw) — here the max* function itself is overstated.
/// Caught by I5b (redeem(maxRedeem) reverts). In-house contract, not from third-party repos.
contract BugMaxRedeemLiesVault is NaiveVault {
    constructor(IERC20 asset_) NaiveVault(asset_) {}

    // BUG: maxRedeem overstated by 1e18 shares over the real balance → redeem(maxRedeem) reverts (_burn underflow).
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf[owner] + 1e18;
    }
}
