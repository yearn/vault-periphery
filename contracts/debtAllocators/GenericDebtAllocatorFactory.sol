// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Clonable} from "@periphery/utils/Clonable.sol";
import {RoleManager} from "../Managers/RoleManager.sol";
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

    /// @notice An even emitted when a new `roleManager` is set.
    event UpdateRoleManager(address indexed roleManager);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice An event emitted when a new debt allocator is added or deployed.
    event NewDebtAllocator(address indexed allocator, address indexed vault);

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

    constructor(
        address _governance,
        address _roleManager
    ) Governance(_governance) {
        // Deploy a dummy allocator as the original.
        original = address(new GenericDebtAllocator(address(1), 0));

        // Set the initial role manager.
        roleManager = _roleManager;
        emit UpdateRoleManager(_roleManager);

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
    ) public virtual returns (address newAllocator) {
        // Clone new allocator off the original.
        newAllocator = _clone();

        // Initialize the new allocator.
        GenericDebtAllocator(newAllocator).initialize(_vault, _minimumChange);

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
            GenericDebtAllocator(allocator(_vault)).shouldUpdateDebt(_strategy);
    }

    /**
     * @notice Helper function to easily get a vaults debt allocator from the role manager.
     * @param _vault Address of the vault to get the allocator for.
     * @return Address of the vaults debt allocator if one exists.
     */
    function allocator(address _vault) public view virtual returns (address) {
        return RoleManager(roleManager).getDebtAllocator(_vault);
    }

    /**
     * @notice Update the Role Manager address.
     * @param _roleManager New role manager address.
     */
    function setRoleManager(
        address _roleManager
    ) external virtual onlyGovernance {
        roleManager = _roleManager;

        emit UpdateRoleManager(_roleManager);
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
