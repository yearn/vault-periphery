// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Clonable} from "@periphery/utils/Clonable.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {GenericDebtAllocator} from "./GenericDebtAllocator.sol";

/**
 * @title YearnV3 Generic Debt Allocator Factory
 * @author yearn.finance
 * @notice
 *  Factory for anyone to easily deploy their own generic
 *  debt allocator for a Yearn V3 Vault.
 */
contract GenericDebtAllocatorFactory is Governance, Clonable {
    /// @notice Revert message for when a debt allocator already exists.
    error AlreadyDeployed(address _allocator);

    /// @notice An event emitted when a new debt allocator is added or deployed.
    event NewDebtAllocator(address indexed allocator, address indexed vault);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice Only allow `governance` or the `roleManager`.
    modifier onlyAuthorized() {
        _isAuthorized();
        _;
    }

    /// @notice Check is `governance` or the `roleManager`.
    function _isAuthorized() internal view {
        require(
            msg.sender == roleManager || msg.sender == governance,
            "!authorized"
        );
    }

    /// @notice Address that is the roleManager for all vaults and can deploy allocators.
    address public roleManager;

    /// @notice Mapping of addresses that are allowed to update debt.
    mapping(address => bool) public keepers;

    /// @notice Mapping of vault => allocator.
    mapping(address => address) public allocators;

    constructor(
        address _governance,
        address _roleManager
    ) Governance(_governance) {
        // Deploy a dummy allocator as the original.
        original = address(new GenericDebtAllocator(address(1), 0));
        roleManager = _roleManager;

        // Default to allow governance to be a keeper.
        keepers[_governance] = true;
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
        return newGenericDebtAllocator(_vault, 0);
    }

    /**
     * @notice Clones a new debt allocator.
     * @param _vault The vault for the allocator to be hooked to.
     * @param _minimumChange The minimum amount needed to trigger debt update.
     * @return newAllocator Address of the new generic debt allocator
     */
    function newGenericDebtAllocator(
        address _vault,
        uint256 _minimumChange
    ) public virtual onlyAuthorized returns (address newAllocator) {
        // Make sure their is not already an allocator deployed for the vault.
        if (allocators[_vault] != address(0))
            revert AlreadyDeployed(allocators[_vault]);

        // Clone new allocator off the original.
        newAllocator = _clone();

        // Initialize the new allocator.
        GenericDebtAllocator(newAllocator).initialize(_vault, _minimumChange);

        // Add it to the
        allocators[_vault] = newAllocator;

        // Emit event.
        emit NewDebtAllocator(newAllocator, _vault);
    }

    /**
     * @notice Check if a strategy's debt should be updated.
     * @dev This should be called by a keeper to decide if a strategies
     * debt should be updated and if so by how much.
     *
     * @param _vault Address of the vault.
     * @param _strategy Address of the strategy to check.
     * @return . Bool representing if the debt should be updated.
     * @return . Calldata if `true` or reason if `false`.
     */
    function shouldUpdateDebt(
        address _vault,
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        return
            GenericDebtAllocator(allocators[_vault]).shouldUpdateDebt(
                _strategy
            );
    }

    /**
     * @notice Set a specific allocator for a specific vault.
     * @dev This will override any previously deployed versions and should
     *   be done with care.
     *
     * @param _vault Address of the vault
     * @param _allocator Address of the debtAllocator.
     */
    function setAllocator(
        address _vault,
        address _allocator
    ) external virtual onlyGovernance {
        allocators[_vault] = _allocator;

        emit NewDebtAllocator(_allocator, _vault);
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
}
