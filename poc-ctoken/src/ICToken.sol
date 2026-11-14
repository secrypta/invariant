// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev A single interface for the cToken target (Compound-V2 ABI), satisfied by both the Naive and Safe cToken.
/// Key difference from ERC-4626: mint is single-argument and returns an ERROR CODE (0 = NO_ERROR), not shares;
/// share accounting is internal (totalSupply/balanceOf), the price is exchangeRateStored (scaled 1e18).
interface ICToken {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function getCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function accrualBlockNumber() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
}
