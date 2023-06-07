// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Registry} from "./Registry.sol";

contract RegistryFactory {
    event NewRegistry(
        address indexed newRegistry,
        address indexed governance,
        string name
    );

    address public immutable releaseRegistry;

    constructor(address _releaseRegistry) {
        releaseRegistry = _releaseRegistry;
    }

    function name() external pure returns (string memory) {
        return "Custom Vault Registry Factory";
    }

    function createNewRegistry(string memory _name) external returns (address) {
        return createNewRegistry(msg.sender, _name);
    }

    function createNewRegistry(
        address _governance,
        string memory _name
    ) public returns (address) {
        Registry newRegistry = new Registry(
            _governance,
            _name,
            releaseRegistry
        );

        emit NewRegistry(address(newRegistry), _governance, _name);
        return address(newRegistry);
    }
}
