// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugMaxWithdrawVault - VULNERABLE demo target of the "max* desync / withdrawal DoS" class
/// @notice A copy of NaiveVault (same correct rounding math), BUT with a per-tx withdrawal limit
/// that maxWithdraw does NOT account for. maxWithdraw(a) honestly returns the full share value,
/// but withdraw reverts if more than WITHDRAW_CAP is requested in a single transaction.
/// A known class: the max* function promises an amount the contract does not actually return in one operation
/// (max*/accounting desync) → partial DoS; integrators that trust maxWithdraw break.
/// Caught by I5 (invariant_I5_maxWithdrawHonored): withdraw(maxWithdraw(a)) reverts.
/// In-house contract, not from third-party repos. No virtual-shares offset (like NaiveVault).
contract BugMaxWithdrawVault {
    using Math for uint256;

    IERC20 public immutable asset;
    uint8 public constant decimals = 18;

    /// BUG: a hard per-tx withdrawal cap that maxWithdraw "does not know about".
    uint256 public constant WITHDRAW_CAP = 1e21;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? shares : shares.mulDiv(totalAssets(), ts, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 ts = totalSupply;
        return ts == 0 ? assets : assets.mulDiv(ts, totalAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) public pure returns (uint256) { return type(uint256).max; }
    function maxMint(address) public pure returns (uint256) { return type(uint256).max; }

    /// BUG: promises the full share value, ignoring the WITHDRAW_CAP that withdraw will impose.
    function maxWithdraw(address owner) public view returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view returns (uint256) { return balanceOf[owner]; }

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
        // BUG: a withdrawal > WITHDRAW_CAP reverts, even though maxWithdraw could return more.
        require(assets <= WITHDRAW_CAP, "BugMaxWithdraw: per-tx cap");
        shares = previewWithdraw(assets);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        assets = previewRedeem(shares);
        require(assets <= WITHDRAW_CAP, "BugMaxWithdraw: per-tx cap");
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
