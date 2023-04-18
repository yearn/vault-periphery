// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CustomRegistry} from "./CustomRegistry.sol";

contract CustomRegistryFactory {
    event NewCustomRegistry(address indexed newCustomRegistry);

    address public immutable original;

    address public immutable registry;

    constructor(string memory _name, address _registry) {
        registry = _registry;

        CustomRegistry _original = new CustomRegistry();

        // Initialize original
        _original.initialize(_name, _registry);

        // Set correct owner
        _original.transferOwnership(msg.sender);

        original = address(_original);

        emit NewCustomRegistry(original);
    }

    function name() external pure returns (string memory) {
        return "Custom Vault Registry Factory";
    }

    function createCustomRegistry(
        string memory _name
    ) external returns (address newCustomRegistry) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(original);

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newCustomRegistry := create(0, clone_code, 0x37)
        }

        // Initialize original
        CustomRegistry(newCustomRegistry).initialize(_name, registry);

        // Set correct owner
        CustomRegistry(newCustomRegistry).transferOwnership(msg.sender);

        emit NewCustomRegistry(newCustomRegistry);
    }
}
