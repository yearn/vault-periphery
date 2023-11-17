// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {GenericDebtAllocator} from "./GenericDebtAllocator.sol";
import {Clonable} from "@periphery/utils/Clonable.sol";

/**
 * @title YearnV3 Generic Debt Allocator Factory
 * @author yearn.finance
 * @notice
 *  Factory for anyone to easily deploy their own generic
 *  debt allocator for a Yearn V3 Vault.
 */
contract GenericDebtAllocatorFactory is Clonable {
    event NewDebtAllocator(address indexed allocator, address indexed vault);

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
    ) external virtual returns (address) {
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
    ) external virtual returns (address) {
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
    ) public virtual returns (address newAllocator) {
        newAllocator = _clone();

        GenericDebtAllocator(newAllocator).initialize(
            _vault,
            _governance,
            _minimumChange
        );

        emit NewDebtAllocator(newAllocator, _vault);
    }
}
