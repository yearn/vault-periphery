// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {DebtAllocator} from "./DebtAllocator.sol";
import {Clonable} from "@periphery/utils/Clonable.sol";
import {RoleManager} from "../Managers/RoleManager.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/**
 * @title YearnV3  Debt Allocator Factory
 * @author yearn.finance
 * @notice
 *  Factory to deploy a debt allocator for a YearnV3 vault.
 */
contract DebtAllocatorFactory is Governance, Clonable {
    /// @notice Revert message for when a debt allocator already exists.
    error AlreadyDeployed(address _allocator);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice An event emitted when the max base fee is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    /// @notice An event emitted when a new debt allocator is added or deployed.
    event NewDebtAllocator(address indexed allocator, address indexed vault);

    /// @notice Max the chains base fee can be during debt update.
    // Will default to max uint256 and need to be set to be used.
    uint256 public maxAcceptableBaseFee;

    /// @notice Mapping of addresses that are allowed to update debt.
    mapping(address => bool) public keepers;

    constructor(address _governance) Governance(_governance) {
        // Deploy a dummy allocator as the original.
        original = address(new DebtAllocator(address(1), 0));

        // Default max base fee to uint max.
        maxAcceptableBaseFee = type(uint256).max;

        // Default to allow governance to be a keeper.
        keepers[_governance] = true;
        emit UpdateKeeper(_governance, true);
    }

    /**
     * @notice Clones a new debt allocator.
     * @dev defaults to msg.sender as the governance role and 0
     *  for the `minimumChange`.
     *
     * @param _vault The vault for the allocator to be hooked to.
     * @return Address of the new debt allocator
     */
    function newDebtAllocator(
        address _vault
    ) external virtual returns (address) {
        return newDebtAllocator(_vault, 0);
    }

    /**
     * @notice Clones a new debt allocator.
     * @param _vault The vault for the allocator to be hooked to.
     * @param _minimumChange The minimum amount needed to trigger debt update.
     * @return newAllocator Address of the new debt allocator
     */
    function newDebtAllocator(
        address _vault,
        uint256 _minimumChange
    ) public virtual returns (address newAllocator) {
        // Clone new allocator off the original.
        newAllocator = _clone();

        // Initialize the new allocator.
        DebtAllocator(newAllocator).initialize(_vault, _minimumChange);

        // Emit event.
        emit NewDebtAllocator(newAllocator, _vault);
    }

    /**
     * @notice Set the max acceptable base fee.
     * @dev This defaults to max uint256 and will need to
     * be set for it to be used.
     *
     * Is denominated in gwei. So 50gwei would be set as 50e9.
     *
     * @param _maxAcceptableBaseFee The new max base fee.
     */
    function setMaxAcceptableBaseFee(
        uint256 _maxAcceptableBaseFee
    ) external virtual onlyGovernance {
        maxAcceptableBaseFee = _maxAcceptableBaseFee;

        emit UpdateMaxAcceptableBaseFee(_maxAcceptableBaseFee);
    }

    /**
     * @notice Set if a keeper can update debt.
     * @param _address The address to set mapping for.
     * @param _allowed If the address can call {update_debt}.
     */
    function setKeeper(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        keepers[_address] = _allowed;

        emit UpdateKeeper(_address, _allowed);
    }

    /**
     * @notice Returns wether or not the current base fee is acceptable
     *   based on the `maxAcceptableBaseFee`.
     * @return . If the current base fee is acceptable.
     */
    function isCurrentBaseFeeAcceptable() external view virtual returns (bool) {
        return maxAcceptableBaseFee >= block.basefee;
    }
}
