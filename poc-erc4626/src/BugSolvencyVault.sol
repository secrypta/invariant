// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BugSolvencyVault — VULNERABLE demo target of the "over-issuance / solvency hole" class
/// @notice A toy vault with a FIXED price of 1 share = 1 wei of asset (convert* 1:1).
/// BUG: on every deposit it mints ONE share MORE than is backed by assets
/// (previewDeposit = assets + 1), i.e. it issues unbacked shares. A known class:
/// the sum of redeemable across holders exceeds the assets → the vault is insolvent.
/// Caught by the strict I3 (solvency, assertLe WITHOUT tolerance): it fires already after the first deposit,
/// whereas I2/I7 with a SLACK=256 tolerance let such "dust" (+1 wei/op) through — hence the strict
/// conservation invariant is required separately from the profit threshold. In-house contract, not from third-party repos.
contract BugSolvencyVault {
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

    // Fixed 1:1 price (toy). The actual hole is in previewDeposit below.
    function convertToShares(uint256 assets) public pure returns (uint256) { return assets; }
    function convertToAssets(uint256 shares) public pure returns (uint256) { return shares; }

    /// BUG: issues 1 share more than the assets brought in → unbacked issuance.
    function previewDeposit(uint256 assets) public pure returns (uint256) { return assets + 1; }
    function previewMint(uint256 shares) public pure returns (uint256) { return shares; }
    function previewWithdraw(uint256 assets) public pure returns (uint256) { return assets; }
    function previewRedeem(uint256 shares) public pure returns (uint256) { return shares; }

    function maxDeposit(address) public pure returns (uint256) { return type(uint256).max; }
    function maxMint(address) public pure returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner) public view returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view returns (uint256) { return balanceOf[owner]; }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets); // assets + 1 (bug: unbacked share)
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
