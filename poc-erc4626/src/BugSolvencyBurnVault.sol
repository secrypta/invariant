// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BugSolvencyBurnVault - 3rd I3 mechanism (over-issuance, via the burn branch).
/// @notice Fixed 1:1 price, but on withdrawal 1 share LESS is burned than is paid out in assets: redeem/withdraw
/// return the full value but _burn(shares−1) → a "phantom" share stays with the owner, Σ shares > assets.
/// A different mechanism than BugSolvency (deposit) and BugSolvencyMint (mint) - the leak is on the BURN. Dust (+1/withdrawal) ⇒
/// the strict I3 catches it, I2 (SLACK) lets it through. Caught by I3 (Σ redeemable > totalAssets). In-house contract, not from third-party repos.
contract BugSolvencyBurnVault {
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
        _burnLess(owner, shares); // BUG: burns 1 less
        asset.transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burnLess(owner, shares); // BUG: burns 1 less
        asset.transfer(receiver, assets);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    /// BUG: burns 1 share less than due → a phantom share stays with the owner.
    function _burnLess(address from, uint256 amount) internal {
        uint256 burn = amount > 0 ? amount - 1 : 0;
        balanceOf[from] -= burn;
        totalSupply -= burn;
    }
}
