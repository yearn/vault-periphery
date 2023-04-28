// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC4626Mock, IERC20Metadata} from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";

interface IRegistry {
    function newStrategy(address, address) external;
}

contract MockStrategy is ERC4626Mock {

    constructor(IERC20Metadata _asset, address _registry) ERC4626Mock(_asset, "test strategy", "tsStrat") {
        // Issue a call to the Registry
        IRegistry(_registry).newStrategy(address(this), address(_asset));
    }
}