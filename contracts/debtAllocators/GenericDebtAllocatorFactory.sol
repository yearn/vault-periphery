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
    event NewDebtAllocator(address indexed allocator, address indexed vault);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    modifier onlyAuthorized() {
        _isAuthorized();
        _;
    }

    function _isAuthorized() internal view {
        require(
            msg.sender == roleManager || msg.sender == governance,
            "!authorized"
        );
    }

    function _isKeeper() internal view virtual {
        require(keepers[msg.sender], "!keeper");
    }

    address public roleManager;

    /// @notice Mapping of addresses that are allowed to update debt.
    mapping(address => bool) public keepers;

    /// @notice Mapping of vault => allocator.
    mapping(address => address) public allocators;

    constructor(
        address _governance,
        address _roleManager
    ) Governance(_governance) {
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
     * @return newAllocator Address of the new generic debt allocator
     */
    function newGenericDebtAllocator(
        address _vault,
        uint256 _minimumChange
    ) public virtual onlyAuthorized returns (address newAllocator) {
        require(allocators[_vault] == address(0), "already deployed");

        newAllocator = _clone();

        GenericDebtAllocator(newAllocator).initialize(_vault, _minimumChange);

        allocators[_vault] = newAllocator;

        emit NewDebtAllocator(newAllocator, _vault);
    }

    function shouldUpdateDebt(
        address _vault,
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        return
            GenericDebtAllocator(allocators[_vault]).shouldUpdateDebt(
                _strategy
            );
    }

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
