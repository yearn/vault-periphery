// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IProtocolAddressProvider} from "../interfaces/IProtocolAddressProvider.sol";

contract YearnV3SetupManager {

    address public immutable protocolAddressProvider;

    constructor(address _addressProvider) {
        protocolAddressProvider = _addressProvider;
    }
}