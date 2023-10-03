// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IVault} from "../../interfaces/IVault.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

/**
 * @title YearnV3 Permissionless Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Permissionless Debt Allocator is meant to be used alongside
 *  a Yearn V3 vault.
 */
contract PermissionlessDebtAllocator {
    // Struct that contains the address of the strategy and its best allocation.
    struct Allocation {
        // Address of the strategy.
        address strategy;
        // Debt for the strategy to end with.
        // Can take 79 Billion 18 decimal tokens.
        int96 newDebt;
    }

    // Contract that holds the logic and oracles for each strategy.
    AprOracle internal constant aprOracle =
        AprOracle(0x02b0210fC1575b38147B232b40D7188eF14C04f2);

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
    ) public {
        // Validate inputs account for all vault assets.
        validateAllocation(_vault, _newAllocations);

        // Get the current and expected APR of the vault.
        (uint256 _currentApr, uint256 _expectedApr) = getCurrentAndExpectedApr(
            _vault,
            _newAllocations
        );

        require(_expectedApr > _currentApr, "bad");

        // Move funds
        _allocate(_vault, _newAllocations);

        // Validate the APR we are earning is higher.
        (uint256 _newCurrentApr, ) = getCurrentAndExpectedApr(
            _vault,
            _newAllocations
        );

        require(_newCurrentApr > _currentApr, "fail");
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
    ) public view {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return;

        // Always first account for the amount idle in the vault.
        uint256 _accountedFor = IVault(_vault).totalIdle();
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            // Add the debt for each strategy in the array.
            _accountedFor += IVault(_vault)
                .strategies(_newAllocations[i].strategy)
                .current_debt;
        }

        // Make sure the ending amounts are the same.
        require(_totalAssets == _accountedFor, "cheater");
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
    ) public view returns (uint256 _currentApr, uint256 _expectedApr) {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return (0, 0);

        Allocation memory _allocation;
        address _strategy;
        uint256 _currentDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _allocation = _newAllocations[i];
            _strategy = _allocation.strategy;
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;

            // Get the current weighted APR the strategy is earning
            uint256 _strategyApr = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            // Add to the amount currently being earned.
            _currentApr += _strategyApr;

            // If the strategies debt is not changing.
            if (_currentDebt == uint256(int256(_allocation.newDebt))) {
                // No need to call the APR oracle again.
                _expectedApr += _strategyApr;
            } else {
                // We add what its expected to yield and its new expected debt
                _expectedApr += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_allocation.newDebt) - int256(_currentDebt)
                ) * uint256(int256(_allocation.newDebt)));
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
        Allocation memory _allocation;
        uint256 _newDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _allocation = _newAllocations[i];
            _newDebt = uint256(int256(_allocation.newDebt));

            // Get the current amount the strategy holds.
            uint256 _currentDebt = IVault(_vault)
                .strategies(_allocation.strategy)
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
                        _allocation.strategy,
                        _currentDebt
                    ) !=
                    0)
            ) {
                IVault(_vault).process_report(_allocation.strategy);
            }

            // Allocate the new debt.
            IVault(_vault).update_debt(_allocation.strategy, _newDebt);
        }
    }
}
