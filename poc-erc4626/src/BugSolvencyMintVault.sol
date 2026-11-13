// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BugSolvencyMintVault — 2nd I3 mechanism (over-issuance, via the mint branch).
/// @notice Fixed 1:1 price (like BugSolvencyVault), but the unbacked share is printed on the MINT branch (not deposit):
/// mint(shares) pulls `shares` assets but mints `shares+1` shares. Σ shares > assets → insolvency.
/// Differs from BugSolvencyVault (+1 on deposit there). The dust leak (+1/mint) ⇒ the strict I3 catches it, the profit
/// threshold I2 (SLACK) lets it through. Caught by I3 (Σ redeemable > totalAssets). In-house contract, not from third-party repos.
contract BugSolvencyMintVault {
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

    function convertToShares(uint256 assets) public pure returns (uint256) { return assets; }
    function convertToAssets(uint256 shares) public pure returns (uint256) { return shares; }
    function previewDeposit(uint256 assets) public pure returns (uint256) { return assets; }
    function previewMint(uint256 shares) public pure returns (uint256) { return shares; }
    function previewWithdraw(uint256 assets) public pure returns (uint256) { return assets; }
    function previewRedeem(uint256 shares) public pure returns (uint256) { return shares; }

    function maxDeposit(address) public pure returns (uint256) { return type(uint256).max; }
    function maxMint(address) public pure returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner) public view returns (uint256) { return convertToAssets(balanceOf[owner]); }
    function maxRedeem(address owner) public view returns (uint256) { return balanceOf[owner]; }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets); // correct (1:1)
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares); // pulls `shares` assets
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares + 1); // BUG: unbacked share on the mint branch
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
