// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {DebtAllocator} from "./DebtAllocator.sol";
import {Clonable} from "@periphery/utils/Clonable.sol";

/**
 * @title YearnV3 Debt Allocator Factory
 * @author yearn.finance
 * @notice
 *  Factory to deploy a debt allocator for a YearnV3 vault.
 */
contract DebtAllocatorFactory is Clonable {
    /// @notice An event emitted when a new debt allocator is added or deployed.
    event NewDebtAllocator(
        address indexed allocator,
        address indexed governance
    );

    constructor() {
        // Deploy a dummy allocator as the original.
        original = address(new DebtAllocator());
    }

    /**
     * @notice Clones a new debt allocator.
     * @param _governance Address to control the debt allocator.
     * @return newAllocator Address of the new debt allocator
     */
    function newDebtAllocator(
        address _governance
    ) public virtual returns (address newAllocator) {
        // Clone new allocator off the original.
        newAllocator = _clone();

        // Initialize the new allocator.
        DebtAllocator(newAllocator).initialize(_governance);

        // Emit event.
        emit NewDebtAllocator(newAllocator, _governance);
    }
}
