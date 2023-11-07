// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {GenericDebtAllocator} from "./GenericDebtAllocator.sol";

/**
 * @title YearnV3 Generic Debt Allocator Factory
 * @author yearn.finance
 * @notice
 *  Factory for anyone to easily deploy their own generic
 *  debt allocator for a Yearn V3 Vault.
 */
contract GenericDebtAllocatorFactory {
    event NewDebtAllocator(address indexed allocator, address indexed vault);

    // Original allocator to use for cloning.
    address public immutable original;

    constructor() {
        original = address(new GenericDebtAllocator(address(1), address(2), 0));
    }

    /**
     * @notice Clones a new debt allocator.
     * @dev defaults to msg.sender as the governance role and 0
     *  for the `minimumChange`.
     *
     * @param _vault The vault for the allocator to be hooked to.
     * @return Address of the new generic debt allocator
     */
    function newGenericDebtAllocator(
        address _vault
    ) external returns (address) {
        return newGenericDebtAllocator(_vault, msg.sender, 0);
    }

    /**
     * @notice Clones a new debt allocator.
     * @dev defaults to 0 for the `minimumChange`.
     *
     * @param _vault The vault for the allocator to be hooked to.
     * @param _governance Address to serve as governance.
     * @return Address of the new generic debt allocator
     */
    function newGenericDebtAllocator(
        address _vault,
        address _governance
    ) external returns (address) {
        return newGenericDebtAllocator(_vault, _governance, 0);
    }

    /**
     * @notice Clones a new debt allocator.
     * @param _vault The vault for the allocator to be hooked to.
     * @param _governance Address to serve as governance.
     * @return newAllocator Address of the new generic debt allocator
     */
    function newGenericDebtAllocator(
        address _vault,
        address _governance,
        uint256 _minimumChange
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

        GenericDebtAllocator(newAllocator).initialize(
            _vault,
            _governance,
            _minimumChange
        );

        emit NewDebtAllocator(newAllocator, _vault);
    }
}
