// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NaiveVault} from "./NaiveVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugPreviewDepositLiesVault — 2nd I6 mechanism (rounding-direction / preview-accuracy).
/// @notice The share math is correct (inherited from NaiveVault, floor), BUT the view function `previewDeposit`
/// overstates the shares (Ceil — in the user's favor), diverging from the actual `deposit` issuance (floor). An EIP-4626 violation
/// (preview must not overstate the operation result in the user's favor). Differs from BugRoundingVault (where
/// the WHOLE math is inverted) — here only the quote lies. Caught by I6 (Handler: previewDeposit(amt) > actual shares).
/// In-house contract, not from third-party repos.
contract BugPreviewDepositLiesVault is NaiveVault {
    using Math for uint256;

    constructor(IERC20 asset_) NaiveVault(asset_) {}

    // BUG: the quote overstates shares (Ceil); the actual issuance is honest floor (convertToShares).
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Ceil);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = convertToShares(assets); // honest issuance (floor) — DIVERGES from previewDeposit (ceil)
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }
}
