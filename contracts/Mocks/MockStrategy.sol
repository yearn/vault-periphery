// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC4626Mock, IERC20Metadata} from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";

interface IRegistry {
    function newStrategy(address, address) external;
}

contract MockStrategy is ERC4626Mock {
    string public apiVersion;

    constructor(
        IERC20Metadata _asset,
        string memory _apiVersion
    ) ERC4626Mock(_asset, "test strategy", "tsStrat") {
        apiVersion = _apiVersion;
    }
}
