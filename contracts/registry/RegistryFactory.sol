// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Registry} from "./Registry.sol";

contract RegistryFactory {
    event NewRegistry(address indexed newRegistry);

    address public immutable original;

    address public immutable releaseRegistry;

    constructor(string memory _name, address _releaseRegistry) {
        releaseRegistry = _releaseRegistry;

        Registry _original = new Registry();

        // Initialize original
        _original.initialize(msg.sender, _name, _releaseRegistry);

        original = address(_original);

        emit NewRegistry(original);
    }

    function name() external pure returns (string memory) {
        return "Custom Vault Registry Factory";
    }

    function createNewRegistry(
        string memory _name
    ) external returns (address newRegistry) {
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
            newRegistry := create(0, clone_code, 0x37)
        }

        // Initialize original
        Registry(newRegistry).initialize(msg.sender, _name, releaseRegistry);

        emit NewRegistry(newRegistry);
    }
}
