// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Registry} from "./Registry.sol";

/**
 * @title YearnV3 Registry Factory
 * @author yearn.finance
 * @notice
 *  Factory for anyone to easily deploy their own Registry.
 */
contract RegistryFactory {
    event NewRegistry(
        address indexed newRegistry,
        address indexed governance,
        string name
    );

    // The release registry to use for all Registries.
    address public immutable releaseRegistry;

    constructor(address _releaseRegistry) {
        releaseRegistry = _releaseRegistry;
    }

    function name() external pure virtual returns (string memory) {
        return "Custom Vault Registry Factory";
    }

    /**
     * @notice Deploy a new Registry.
     * @dev Default to msg.sender for governance.
     * @param _name The name of the new registry.
     * @return Address of the new Registry.
     */
    function createNewRegistry(
        string memory _name
    ) external virtual returns (address) {
        return createNewRegistry(_name, msg.sender);
    }

    /**
     * @notice Deploy a new Registry.
     * @param _name The name of the new registry.
     * @param _governance Address to set as governance.
     * @return Address of the new Registry.
     */
    function createNewRegistry(
        string memory _name,
        address _governance
    ) public virtual returns (address) {
        Registry newRegistry = new Registry(
            _governance,
            _name,
            releaseRegistry
        );

        emit NewRegistry(address(newRegistry), _governance, _name);
        return address(newRegistry);
    }
}
