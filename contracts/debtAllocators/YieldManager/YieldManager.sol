// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

import {Governance} from "@periphery/utils/Governance.sol";

import {StrategyManager, IStrategy} from "./StrategyManager.sol";

/**
 * @title YearnV3 Yield Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Debt Allocator is meant to be used alongside
 *  a Yearn V3 vault to allocate funds to the optimal strategy.
 */
contract YieldDebtAllocator is Governance {
    // Struct that contains the address of the strategy and its best allocation.
    struct Allocation {
        // Address of the strategy.
        address strategy;
        // Debt for the strategy to end with.
        // Can take 79 Billion 18 decimal tokens.
        uint96 newDebt;
    }

    modifier onlyAllocatorsOrOpen() {
        _isAllocatorOrOpen();
        _;
    }

    function _isAllocatorOrOpen() internal view {
        require(allocators[msg.sender] || open, "!allocator or open");
    }

    // Contract that holds the logic and oracles for each strategy.
    AprOracle internal constant aprOracle =
        AprOracle(0x02b0210fC1575b38147B232b40D7188eF14C04f2);

    mapping(address => bool) public allocators;

    bool public open;

    address public immutable strategyManager;

    constructor(
        address _governance,
        address _strategyManager
    ) Governance(_governance) {
        strategyManager = _strategyManager;
    }

    /**
     * @notice Update a `_vault`s allocation of debt.
     * @dev This takes the address of a vault and an array of
     * its strategies and their specific allocation.
     *
     * The `_newAllocations` array should:
     *   - Contain all strategies that hold any amount of debt from the vault
     *       even if the debt wont be adjusted in order to get the correct
     *       on chain APR.
     *   - Be ordered so that all debt decreases are at the beginning of the array
     *       and debt increases at the end.
     *
     * It is expected that the proposer does all needed checks for values such
     * as max_debt, maxWithdraw, min total Idle etc. that are enforced on debt
     * updates at the vault level.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function updateAllocationPermissioned(
        address _vault,
        Allocation[] memory _newAllocations
    ) public onlyGovernance {
        // Move funds
        _allocate(_vault, _newAllocations);
    }

    /**
     * @notice Update a `_vault`s allocation of debt.
     * @dev This takes the address of a vault and an array of
     * its strategies and their specific allocation.
     *
     * The `_newAllocations` array should:
     *   - Contain all strategies that hold any amount of debt from the vault
     *       even if the debt wont be adjusted in order to get the correct
     *       on chain APR.
     *   - Be ordered so that all debt decreases are at the beginning of the array
     *       and debt increases at the end.
     *
     * It is expected that the proposer does all needed checks for values such
     * as max_debt, maxWithdraw, min total Idle etc. that are enforced on debt
     * updates at the vault level.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function updateAllocation(
        address _vault,
        Allocation[] memory _newAllocations
    )
        external
        onlyAllocatorsOrOpen
        returns (uint256 _currentApr, uint256 _newApr)
    {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return (0, 0);

        // Always first account for the amount idle in the vault.
        uint256 _accountedFor = IVault(_vault).totalIdle();
        address _strategy;
        uint256 _currentDebt;
        uint256 _newDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _strategy = _newAllocations[i].strategy;
            _newDebt = uint256(_newAllocations[i].newDebt);
            // Get the debt the strategy current has.
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;
            // Add to what we have accounted for.
            _accountedFor += _currentDebt;

            // Get the current weighted APR the strategy is earning
            uint256 _strategyApr = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            // Add to the amount currently being earned.
            _currentApr += _strategyApr;

            // If no change move to the next strategy.
            if (_newDebt == _currentDebt) {
                // We assume the new apr will be the same as current.
                _newApr += _strategyApr;
                continue;
            }

            if (_currentDebt > _newDebt) {
                // We need to report profits and have them immediately unlock to not loose out on locked profit.
                // NOTE: Should this all be put in the strategy manager

                // Get the current unlock rate.
                uint256 profitUnlock = IStrategy(_strategy)
                    .profitMaxUnlockTime();

                // Create array fo call data for the strategy manager to use
                bytes[] memory _calldataArray = new bytes[](3);
                
                // Set profit unlock to 0.
                _calldataArray[0] = abi.encodeCall(
                    IStrategy(_strategy).setProfitMaxUnlockTime,
                    0
                );
                // Report profits.
                _calldataArray[1] = abi.encodeWithSelector(
                    IStrategy(_strategy).report.selector
                );
                // Set profit unlock back to original.
                _calldataArray[2] = abi.encodeCall(
                    IStrategy(_strategy).setProfitMaxUnlockTime,
                    profitUnlock
                );

                // Forward all calls to strategy.
                StrategyManager(strategyManager).forwardCalls(
                    _strategy,
                    _calldataArray
                );

                // If we are pulling all debt from a strategy OR we are decreasing
                // debt and the strategy has any unrealised losses we first need to
                // report the strategy.
                if (
                    _newDebt == 0 ||
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) !=
                    0
                ) {
                    IVault(_vault).process_report(_strategy);
                }
            }

            // TODO: validate losses based on ending totalAssets
            // Allocate the new debt.
            IVault(_vault).update_debt(_strategy, _newDebt);

            // Get the new APR
            _newApr += aprOracle.getStrategyApr(_strategy, 0) * _newDebt;
        }

        // Make sure the ending amounts are the same otherwise rates could be wrong.
        require(_totalAssets == _accountedFor, "cheater");

        // Adjust both rates based on the total assets to get the weighted APR.
        _currentApr /= _totalAssets;
        _newApr /= _totalAssets;

        require(_newApr > _currentApr, "fail");
    }

    /**
     * @notice Validates that all assets of a vault are accounted for in
     * the proposed allocation array.
     *
     * If not the APR calculation will not be correct.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function validateAllocation(
        address _vault,
        Allocation[] memory _newAllocations
    ) external view returns (bool) {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return false;

        // Always first account for the amount idle in the vault.
        uint256 _accountedFor = IVault(_vault).totalIdle();
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            // Add the debt for each strategy in the array.
            _accountedFor += IVault(_vault)
                .strategies(_newAllocations[i].strategy)
                .current_debt;
        }

        // Make sure the ending amounts are the same.
        return _totalAssets == _accountedFor;
    }

    /**
     * @notice Get the current apr the vault is earning and the expected
     * APR based on the proposed changes.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function getCurrentAndExpectedApr(
        address _vault,
        Allocation[] memory _newAllocations
    ) external view returns (uint256 _currentApr, uint256 _expectedApr) {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return (0, 0);

        uint256 _newDebt;
        address _strategy;
        uint256 _currentDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _newDebt = uint256(_newAllocations[i].newDebt);
            _strategy = _newAllocations[i].strategy;
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;

            // Get the current weighted APR the strategy is earning
            uint256 _strategyApr = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            // Add to the amount currently being earned.
            _currentApr += _strategyApr;

            // If the strategies debt is not changing.
            if (_currentDebt == _newDebt) {
                // No need to call the APR oracle again.
                _expectedApr += _strategyApr;
            } else {
                // We add what its expected to yield and its new expected debt
                _expectedApr += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_newDebt) - int256(_currentDebt)
                ) * _newDebt);
            }
        }

        // Adjust both based on the total assets to get the weighted APR.
        _currentApr /= _totalAssets;
        _expectedApr /= _totalAssets;
    }

    /**
     * @notice Allocate a vaults debt based on the new proposed Allocation.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function _allocate(
        address _vault,
        Allocation[] memory _newAllocations
    ) internal {
        address _strategy;
        uint256 _newDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _strategy = _newAllocations[i].strategy;
            _newDebt = uint256(_newAllocations[i].newDebt);

            // Get the current amount the strategy holds.
            uint256 _currentDebt = IVault(_vault)
                .strategies(_strategy)
                .current_debt;

            // If no change move to the next strategy.
            if (_newDebt == _currentDebt) continue;

            // If we are pulling all debt from a strategy OR we are decreasing
            // debt and the strategy has any unrealised losses we first need to
            // report the strategy.
            if (
                _newDebt == 0 ||
                (_currentDebt > _newDebt &&
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) !=
                    0)
            ) {
                IVault(_vault).process_report(_strategy);
            }

            // Allocate the new debt.
            IVault(_vault).update_debt(_strategy, _newDebt);
        }
    }

    function setAllocators(
        address _address,
        bool _allowed
    ) external onlyGovernance {
        allocators[_address] = _allowed;
    }

    function setOpen(bool _open) external onlyGovernance {
        open = _open;
    }
}
