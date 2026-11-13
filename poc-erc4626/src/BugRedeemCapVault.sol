// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NaiveVault} from "./NaiveVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BugRedeemCapVault — 3rd I5 mechanism (max* desync, redeem branch, different mechanism).
/// @notice The math and maxRedeem are correct, BUT redeem has a per-tx share cap REDEEM_CAP that maxRedeem
/// "does not know about". redeem(maxRedeem(a)) reverts when balance > CAP. Analogous to BugMaxWithdrawVault, but on shares/redeem
/// (not assets/withdraw) and a different mechanism than BugMaxRedeemLies (cap vs overstated quote). Caught by I5b.
/// In-house contract, not from third-party repos.
contract BugRedeemCapVault is NaiveVault {
    uint256 public constant REDEEM_CAP = 1e21;

    constructor(IERC20 asset_) NaiveVault(asset_) {}

    // BUG: per-tx share cap on redeem, not reflected in maxRedeem.
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        require(shares <= REDEEM_CAP, "BugRedeemCap: per-tx cap");
        return super.redeem(shares, receiver, owner);
    }
}
