// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BugDeadSharesVault - VULNERABLE demo target: WEAK protection against donation inflation (an I2 backstop)
/// @notice A copy of NaiveVault, but with a REAL yet INSUFFICIENT protection: on the first deposit it mints
/// a fixed minimum of "dead" shares to address(0) (Uniswap V2 MINIMUM_LIQUIDITY style), instead of
/// OZ's scalable virtual shares. The fixed DEAD shares are negligible when the attacker himself
/// makes a large deposit: his share ≈ 100%, the protection does not scale → donation inflation goes through again.
/// The point is to show that the I2 gate catches the CLASS "attacker profit", not one contract: the same I2 fails
/// here too (a different broken protection mechanism) and holds on OZVault(offset=3). In-house contract, not from third-party repos.
contract BugDeadSharesVault {
    using Math for uint256;

    IERC20 public immutable asset;
    uint8 public constant decimals = 18;

    /// Fixed minimum of "dead" shares (one-time, does NOT scale - that is the weakness).
    uint256 public constant DEAD_SHARES = 1e3;

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
        shares = previewDeposit(assets);
        asset.transferFrom(msg.sender, address(this), assets);
        // Weak protection: "burn" a fixed minimum of shares to address(0) once.
        if (totalSupply == 0) _mint(address(0), DEAD_SHARES);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        if (totalSupply == 0) _mint(address(0), DEAD_SHARES);
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
