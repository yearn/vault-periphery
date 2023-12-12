// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

import {Governance} from "@periphery/utils/Governance.sol";

import {StrategyManager} from "./StrategyManager.sol";

/**
 * @title YearnV3 Yield Yield Based Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Debt Allocator is meant to be used alongside
 *  a Yearn V3 vault to allocate funds to the optimal strategy.
 */
contract YieldManager is Governance {
    /// @notice An event emitted when the max debt update loss is updated.
    event UpdateMaxDebtUpdateLoss(uint256 newMaxDebtUpdateLoss);

    // Struct that contains the address of the strategy and its best allocation.
    struct Allocation {
        // Address of the strategy.
        address strategy;
        // Debt for the strategy to end with.
        // Can take 79 Billion 18 decimal tokens.
        uint96 newDebt;
    }

    /// @notice Only allow the sender to be an allocator if not opened.
    modifier onlyAllocatorsOrOpen() {
        _isAllocatorOrOpen();
        _;
    }

    /// @notice Check if it has been opened or is an allocator.
    function _isAllocatorOrOpen() internal view {
        require(allocators[msg.sender] || open, "!allocator or open");
    }

    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Contract that holds the logic and oracles for each strategy.
    AprOracle internal constant aprOracle =
        AprOracle(0x02b0210fC1575b38147B232b40D7188eF14C04f2);

    /// @notice Flag to set to allow anyone to propose allocations.
    bool public open;

    /// @notice Max loss to accept on debt updates in basis points.
    uint256 public maxDebtUpdateLoss;

    /// @notice Address that should hold the strategies `management` role.
    address public immutable strategyManager;

    /// @notice Addresses that are allowed to propose allocations.
    mapping(address => bool) public allocators;

    constructor(
        address _governance,
        address _strategyManager
    ) Governance(_governance) {
        strategyManager = _strategyManager;
        // Default to 1 BP loss
        maxDebtUpdateLoss = 1;
    }

    /**
     * @notice Update a `_vault`s allocation of debt.
     * @dev This takes the address of a vault and an array of
     * its strategies and their specific allocation.
     *
     * The `_newAllocations` array should:
     *   - Be ordered so that all debt decreases are at the beginning of the array
     *       and debt increases at the end.
     *
     * This will not do any APR checks and assumes the sender has completed
     * any and all necessary checks before sending.
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
        returns (uint256 _currentYield, uint256 _afterYield)
    {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return (0, 0);

        // Always first account for the amount idle in the vault.
        uint256 _accountedFor = IVault(_vault).totalIdle();
        // Create local variables used through loops.
        address _strategy;
        uint256 _currentDebt;
        uint256 _newDebt;
        uint256 _loss;
        uint256 _gain;
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
            _currentYield += _strategyApr;

            // If no change move to the next strategy.
            if (_newDebt == _currentDebt) {
                // We assume the new apr will be the same as current.
                _afterYield += _strategyApr;
                continue;
            }

            // If we are withdrawing.
            if (_currentDebt > _newDebt) {
                // If we are pulling all debt from a strategy.
                if (_newDebt == 0) {
                    // We need to report profits and have them immediately unlock to not lose out on locked profit.
                    StrategyManager(strategyManager).reportFullProfit(
                        _strategy
                    );

                    // Report profits on the vault.
                    (uint256 reportedProfit, uint256 reportedLoss) = IVault(
                        _vault
                    ).process_report(_strategy);

                    // Track for debt reduction loss checks.
                    _loss += reportedLoss;
                    _gain += reportedProfit;
                } else if (
                    // We cannot decrease debt if the strategy has any unrealised losses.
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) != 0
                ) {
                    // Realize the loss.
                    (, uint256 reportedLoss) = IVault(_vault).process_report(
                        _strategy
                    );
                    // Track for debt reduction loss checks.
                    _loss += reportedLoss;
                }

                // Allocate the new debt.
                IVault(_vault).update_debt(_strategy, _newDebt);

                // Validate losses based on ending totalAssets adjusted for any realized loss or gain.
                uint256 afterAssets = IVault(_vault).totalAssets() +
                    _loss -
                    _gain;

                // If a loss was realized on just the debt update.
                if (afterAssets < _totalAssets) {
                    // Make sure its within the range.
                    require(
                        _totalAssets - afterAssets <=
                            (_currentDebt * maxDebtUpdateLoss) / MAX_BPS,
                        "too much loss"
                    );
                }
            } else {
                // If adding just Allocate the new debt.
                IVault(_vault).update_debt(_strategy, _newDebt);
            }

            // Get the new APR
            if (_newDebt != 0) {
                _afterYield +=
                    aprOracle.getStrategyApr(_strategy, 0) *
                    _newDebt;
            }
        }

        // Make sure the ending amounts are the same otherwise rates could be wrong.
        require(_totalAssets == _accountedFor, "cheater");
        require(_afterYield > _currentYield, "fail");
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
     * @notice Get the current weighted yield the vault is earning and the expected
     * APR based on the proposed changes.
     *
     * Must divide by the totalAssets to get the APR as 1e18.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     */
    function getCurrentAndExpectedYield(
        address _vault,
        Allocation[] memory _newAllocations
    ) external view returns (uint256 _currentYield, uint256 _expectedYield) {
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
            _currentYield += _strategyApr;

            // If the strategies debt is not changing.
            if (_currentDebt == _newDebt) {
                // No need to call the APR oracle again.
                _expectedYield += _strategyApr;
            } else {
                // We add what its expected to yield and its new expected debt
                _expectedYield += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_newDebt) - int256(_currentDebt)
                ) * _newDebt);
            }
        }
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
        uint256 _loss;
        uint256 _gain;
        uint256 _totalAssets = IVault(_vault).totalAssets();
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _strategy = _newAllocations[i].strategy;
            _newDebt = uint256(_newAllocations[i].newDebt);

            // Get the current amount the strategy holds.
            uint256 _currentDebt = IVault(_vault)
                .strategies(_strategy)
                .current_debt;

            // If no change move to the next strategy.
            if (_newDebt == _currentDebt) continue;

            if (_newDebt < _currentDebt) {
                // If we are pulling all debt from a strategy.
                if (_newDebt == 0) {
                    // We need to report profits and have them immediately unlock to not lose out on locked profit.
                    StrategyManager(strategyManager).reportFullProfit(
                        _strategy
                    );

                    // Report on the vault.
                    (uint256 reportedProfit, uint256 reportedLoss) = IVault(
                        _vault
                    ).process_report(_strategy);

                    // Track for debt reduction loss checks.
                    _loss += reportedLoss;
                    _gain += reportedProfit;
                } else if (
                    // We cannot decrease debt if the strategy has any unrealised losses.
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) != 0
                ) {
                    // Realize the loss.
                    (, uint256 reportedLoss) = IVault(_vault).process_report(
                        _strategy
                    );
                    // Track for debt reduction loss checks.
                    _loss += reportedLoss;
                }

                // Allocate the new debt.
                IVault(_vault).update_debt(_strategy, _newDebt);

                // Validate losses based on ending totalAssets adjusted for any realized loss or gain.
                uint256 afterAssets = IVault(_vault).totalAssets() +
                    _loss -
                    _gain;

                // If a loss was realized on just the debt update.
                if (afterAssets < _totalAssets) {
                    // Make sure its within the range.
                    require(
                        _totalAssets - afterAssets <=
                            (_currentDebt * maxDebtUpdateLoss) / MAX_BPS,
                        "too much loss"
                    );
                }
            } else {
                // If adding just Allocate the new debt.
                IVault(_vault).update_debt(_strategy, _newDebt);
            }
        }
    }

    /**
     * @notice Sets the permission for an allocator.
     * @param _address The address of the allocator.
     * @param _allowed The permission to set for the allocator.
     */
    function setAllocator(
        address _address,
        bool _allowed
    ) external onlyGovernance {
        allocators[_address] = _allowed;
    }

    /**
     * @notice Sets the open status of the contract.
     * @param _open The new open status to set.
     */
    function setOpen(bool _open) external onlyGovernance {
        open = _open;
    }

    /**
     * @notice Set the max loss in Basis points to allow on debt updates.
     * @dev Withdrawing during debt updates use {redeem} which allows for 100% loss.
     *      This can be used to assure a loss is not realized on redeem outside the tolerance.
     * @param _maxDebtUpdateLoss The max loss to accept on debt updates.
     */
    function setMaxDebtUpdateLoss(
        uint256 _maxDebtUpdateLoss
    ) external virtual onlyGovernance {
        require(_maxDebtUpdateLoss <= MAX_BPS, "higher than max");
        maxDebtUpdateLoss = _maxDebtUpdateLoss;

        emit UpdateMaxDebtUpdateLoss(_maxDebtUpdateLoss);
    }
}
