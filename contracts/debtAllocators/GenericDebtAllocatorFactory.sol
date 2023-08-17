// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {GenericDebtAllocator} from "./GenericDebtAllocator.sol";

contract GenericDebtAllocatorFactory {
    event NewDebtAllocator(address indexed allocator, address indexed vault);

    address public immutable original;

    constructor(address _vault, address _governance) {
        original = address(new GenericDebtAllocator(_vault, _governance));

        emit NewDebtAllocator(original, _vault);
    }

    function newGenericDebtAllocator(
        address _vault
    ) external returns (address) {
        return newGenericDebtAllocator(_vault, msg.sender);
    }

    function newGenericDebtAllocator(
        address _vault,
        address _governance
    ) public returns (address newAllocator) {
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
            newAllocator := create(0, clone_code, 0x37)
        }

        GenericDebtAllocator(newAllocator).inizialize(_vault, _governance);

        emit NewDebtAllocator(newAllocator, _vault);
    }
}
