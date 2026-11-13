// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugMinDepositVault — VULNERABLE demo target: SECURITY THEATER against donation inflation (2nd I2 target)
/// @notice A copy of NaiveVault with a "protection" in the form of a minimum deposit (require assets >= MIN_DEPOSIT).
/// The author reasoned: "banning a 1-wei deposit will stop the first-depositor attack". But the share math
/// is NOT touched (bare naive), so the attacker simply deposits MIN_DEPOSIT (not 1 wei), donates and
/// rounds the victim's deposit to zero — the attack goes through. This is a DIFFERENT broken protection mechanism
/// than bare NaiveVault (there is a "protection", but it misses the point) and than the weak dead-shares/offset=0.
/// The point is to confirm that the I2 gate catches the CLASS "attacker profit", not a specific implementation:
/// I2 fails here too and holds on OZVault(offset=3). In-house contract, not from third-party repos.
contract BugMinDepositVault {
    using Math for uint256;

    IERC20 public immutable asset;
    uint8 public constant decimals = 18;

    /// "Protection": a minimum deposit. Does NOT fix the share math → donation inflation still works.
    uint256 public constant MIN_DEPOSIT = 1e6;

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
    function maxWithdraw(address owner) public view returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view returns (uint256) { return balanceOf[owner]; }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        // Security theater: cut off the dust, but leave the share math untouched.
        require(assets >= MIN_DEPOSIT, "BugMinDeposit: deposit too small");
        shares = previewDeposit(assets);
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        require(assets >= MIN_DEPOSIT, "BugMinDeposit: deposit too small");
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
