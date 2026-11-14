// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title OZVault - FIXED demo target (false-positive control)
/// @notice OpenZeppelin ERC4626 (openzeppelin-contracts v5.1.0) with a virtual-shares offset.
/// _decimalsOffset() is set in the constructor: 0 (baseline run) or 3 (hardened).
/// Virtual shares dilute the donation → the donation/inflation attack does not go through.
contract OZVault is ERC4626 {
    uint8 private immutable _off;

    constructor(IERC20 asset_, uint8 offset_) ERC4626(asset_) ERC20("OZ Vault", "ozVAULT") {
        _off = offset_;
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _off;
    }
}
