// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {YearnRoleManager} from "./YearnRoleManager.sol";

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

contract RoleManagerGovernance is Governance2Step {
    /// @notice Position ID for "daddy".
    bytes32 public constant DADDY = keccak256("Daddy");
    /// @notice Position ID for "brain".
    bytes32 public constant BRAIN = keccak256("Brain");

    YearnRoleManager public immutable roleManager;

    constructor(
        address _roleManager,
        address _governance
    ) Governance2Step(_governance) {
        roleManager = YearnRoleManager(_roleManager);
    }

    // Forward all governance functions

    // Allow deployments to be permissionless
    function newVault(
        address _asset,
        uint256 _category
    ) external returns (address) {
        return roleManager.newVault(_asset, _category);
    }

    function newVault(
        address _asset,
        uint256 _category,
        uint256 _depositLimit
    ) external onlyGovernance returns (address) {
        return roleManager.newVault(_asset, _category, _depositLimit);
    }

    function newVault(
        address _asset,
        uint256 _category,
        uint256 _depositLimit,
        uint256 _profitMaxUnlockTime
    ) external onlyGovernance returns (address) {
        return
            roleManager.newVault(
                _asset,
                _category,
                _depositLimit,
                _profitMaxUnlockTime
            );
    }

    function addNewVault(
        address _vault,
        uint256 _category
    ) external onlyGovernance {
        roleManager.addNewVault(_vault, _category);
    }

    function addNewVault(
        address _vault,
        uint256 _category,
        address _debtAllocator
    ) external onlyGovernance {
        roleManager.addNewVault(_vault, _category, _debtAllocator);
    }

    function removeRoles(
        address[] calldata _vaults,
        address _holder,
        uint256 _role
    ) external onlyGovernance {
        roleManager.removeRoles(_vaults, _holder, _role);
    }

    function setPositionRoles(
        bytes32 _position,
        uint256 _newRoles
    ) external onlyGovernance {
        roleManager.setPositionRoles(_position, _newRoles);
    }

    function setPositionHolder(
        bytes32 _position,
        address _newHolder
    ) external onlyGovernance {
        // Can not update who owns these roles
        require(_position != DADDY && _position != BRAIN, "Invalid position");
        roleManager.setPositionHolder(_position, _newHolder);
    }

    function setDefaultProfitMaxUnlock(
        uint256 _newDefaultProfitMaxUnlock
    ) external onlyGovernance {
        roleManager.setDefaultProfitMaxUnlock(_newDefaultProfitMaxUnlock);
    }
}
