// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantBase} from "./InvariantBase.sol";
import {IVault} from "../src/IVault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {BugMaxRedeemLiesVault} from "../src/BugMaxRedeemLiesVault.sol";

contract BugMaxRedeemLiesVaultInvariant is InvariantBase {
    function _deployVault(MockERC20 asset_) internal override returns (IVault) {
        return IVault(address(new BugMaxRedeemLiesVault(asset_)));
    }
}
