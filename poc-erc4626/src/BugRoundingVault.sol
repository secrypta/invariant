// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugRoundingVault — VULNERABLE demo target of the "rounding-direction" class (catalog validation)
/// @notice A copy of NaiveVault, but ALL rounding is flipped IN THE USER'S FAVOR:
///   - on the way in, shares are computed CEIL (the user gets MORE shares than the honest floor);
///   - on the way out, assets are computed CEIL (the vault returns MORE assets);
///   - previewMint/previewWithdraw are also skewed toward the user (pays less / burns less).
/// A known bug class: rounding must always work AGAINST the user (in the vault's favor),
/// otherwise a round-trip deposit→redeem returns more than deposited — free dust extraction.
/// The leak size is ≤1 ulp per operation (< SLACK), so it is caught not by a threshold (I7),
/// but by DIRECTION (I6): previewRedeem(previewDeposit(a)) must be ≤ a; here it is > a.
/// A toy, in-house contract — not from third-party repos. No virtual-shares offset (like NaiveVault).
contract BugRoundingVault {
    using Math for uint256;

    IERC20 public immutable asset;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // --- BUG: shares on the way in round-UP (Ceil) — in the user's favor (should be Floor) ---
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Ceil);
    }

    // --- BUG: assets on the way out round-UP (Ceil) — in the user's favor (should be Floor) ---
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Ceil);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets); // Ceil (bug)
    }

    // --- BUG: previewMint rounds DOWN (Floor) — the user pays FEWER assets (should be Ceil) ---
    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Floor);
    }

    // --- BUG: previewWithdraw rounds DOWN (Floor) — the user burns FEWER shares (should be Ceil) ---
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Floor);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares); // Ceil (bug)
    }

    function maxDeposit(address) public pure returns (uint256) { return type(uint256).max; }
    function maxMint(address) public pure returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner) public view returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view returns (uint256) { return balanceOf[owner]; }

    // --- actions (identical to NaiveVault; only the rounding math above changes) ---
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets);
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }
}
