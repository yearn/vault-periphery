// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {DebtAllocator} from "./DebtAllocator.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @title Debt Allocator Keeper
 * @notice
 *   A small allowlisted wrapper that can be added as a keeper and manager on a
 *   DebtAllocator, while limiting keepers to specific vaults.
 */
contract DebtAllocatorKeeper is Governance, Multicall {
    /// @notice Emitted when a caller is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice Emitted when a vault is added or removed.
    event UpdateAllowedVault(address indexed vault, bool allowed);

    /// @notice The debt allocator this contract forwards updates to.
    address public immutable DEBT_ALLOCATOR;

    /// @notice Mapping of callers allowed to move debt and set ratios through this contract.
    mapping(address => bool) public keepers;

    /// @notice Mapping of vaults allowed to be updated.
    mapping(address => bool) public allowedVaults;

    modifier onlyKeepers() {
        require(keepers[msg.sender], "!keeper");
        _;
    }

    modifier onlyAllowedVault(address _vault) {
        require(allowedVaults[_vault], "!allowed");
        _;
    }

    constructor(address _debtAllocator, address _governance) Governance(_governance) {
        require(_debtAllocator != address(0), "ZERO ADDRESS");
        require(_governance != address(0), "ZERO ADDRESS");

        DEBT_ALLOCATOR = _debtAllocator;
    }

    /**
     * @notice Set if a caller can move debt through this contract.
     * @param _keeper The caller to add or remove.
     * @param _allowed If the caller can move debt.
     */
    function setKeeper(address _keeper, bool _allowed) external virtual onlyGovernance {
        require(_keeper != address(0), "ZERO ADDRESS");

        keepers[_keeper] = _allowed;

        emit UpdateKeeper(_keeper, _allowed);
    }

    /**
     * @notice Set if a vault can be updated.
     * @param _vault The vault whose debt can be moved or ratios can be set.
     * @param _allowed If the vault can be updated.
     */
    function setAllowedVault(address _vault, bool _allowed) public virtual onlyGovernance {
        require(_vault != address(0), "ZERO ADDRESS");

        allowedVaults[_vault] = _allowed;

        emit UpdateAllowedVault(_vault, _allowed);
    }

    /**
     * @notice Move debt through the configured DebtAllocator.
     * @dev This contract must be set as a keeper on the DebtAllocator.
     */
    function update_debt(address _vault, address _strategy, uint256 _targetDebt)
        external
        virtual
        onlyKeepers
        onlyAllowedVault(_vault)
    {
        DebtAllocator(DEBT_ALLOCATOR).update_debt(_vault, _strategy, _targetDebt);
    }

    /**
     * @notice Set a target debt ratio for an allowed vault.
     */
    function setStrategyDebtRatio(address _vault, address _strategy, uint256 _targetRatio)
        external
        virtual
        onlyKeepers
        onlyAllowedVault(_vault)
    {
        DebtAllocator(DEBT_ALLOCATOR).setStrategyDebtRatio(_vault, _strategy, _targetRatio);
    }

    /**
     * @notice Set a target and max debt ratio for an allowed vault.
     */
    function setStrategyDebtRatio(address _vault, address _strategy, uint256 _targetRatio, uint256 _maxRatio)
        external
        virtual
        onlyKeepers
        onlyAllowedVault(_vault)
    {
        DebtAllocator(DEBT_ALLOCATOR).setStrategyDebtRatio(_vault, _strategy, _targetRatio, _maxRatio);
    }
}
