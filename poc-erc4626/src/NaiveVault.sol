// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title NaiveVault — VULNERABLE demo target (D)
/// @notice A minimal ERC-4626 WITHOUT a virtual-shares offset. totalAssets() = the asset balance held by the contract,
/// so a direct transfer (donation) inflates the share price → first-depositor/donation inflation attack.
/// A toy, in-house contract — not from third-party repos. Allowance on withdrawal is not checked (owner==msg.sender in the harness).
contract NaiveVault {
    using Math for uint256;

    IERC20 public immutable asset;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // --- conversion: shares round-down (in the vault's favor), required assets round-up ---
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) public pure virtual returns (uint256) { return type(uint256).max; }
    function maxMint(address) public pure virtual returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner) public view virtual returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view virtual returns (uint256) { return balanceOf[owner]; }

    // --- actions (preview is computed BEFORE the incoming transferFrom — as in canonical ERC-4626) ---
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = previewDeposit(assets);
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }
}
