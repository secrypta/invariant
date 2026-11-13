// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NaiveVault} from "./NaiveVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugPreviewRedeemLiesVault — 3rd I6 mechanism (preview-accuracy / direction).
/// @notice The redeem payout is honest (floor), BUT the view quote `previewRedeem` is overstated (×1.01) — it lies in the user's favor,
/// diverging from the actual payout. Integrators/routers that trust previewRedeem receive less than promised
/// (an EIP-4626 violation: preview must not overstate). Differs from BugRounding (whole math) and
/// BugPreviewDepositLies (quote on the way in). Caught by I6 (Handler: previewRedeem(sh) > actual payout + 1).
/// In-house contract, not from third-party repos.
contract BugPreviewRedeemLiesVault is NaiveVault {
    using Math for uint256;

    constructor(IERC20 asset_) NaiveVault(asset_) {}

    // BUG: the quote is overstated by 1% (should = convertToAssets floor).
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares) * 101 / 100;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        assets = convertToAssets(shares); // honest payout (floor) — DIVERGES from previewRedeem (×1.01)
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }
}
