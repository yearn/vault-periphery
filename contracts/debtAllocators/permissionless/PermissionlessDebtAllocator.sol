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
    struct Allocation {
        address strategy;
        // Can take 79 Billion DAI
        int96 newDebt;
    }

    AprOracle internal constant aprOracle =
        AprOracle(0x02b0210fC1575b38147B232b40D7188eF14C04f2);

    function updateAllocation(
        address _vault,
        Allocation[] memory _newAllocations
    ) public {
        // Validate inputs
        validateAllocation(_vault, _newAllocations);

        // Get the current and expected APR of the vault.
        (uint256 _currentApr, uint256 _expectedApr) = getCurrentAndExpectedApr(
            _vault,
            _newAllocations
        );

        require(_expectedApr > _currentApr, "bad");

        // Move funds
        _allocate(_vault, _newAllocations);
    }

    function validateAllocation(
        address _vault,
        Allocation[] memory _newAllocations
    ) public view {
        uint256 _totalAssets = IVault(_vault).totalAssets();
        if (_totalAssets == 0) return;

        uint256 _accountedFor = IVault(_vault).totalIdle();
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _accountedFor += IVault(_vault)
                .strategies(_newAllocations[i].strategy)
                .current_debt;
        }

        require(_totalAssets == _accountedFor, "cheater!");
    }

    function getCurrentAndExpectedApr(
        address _vault,
        Allocation[] memory _newAllocations
    ) public view returns (uint256 _currentApr, uint256 _expectedApr) {
        uint256 _totalAssets = IVault(_vault).totalAssets();
        if (_totalAssets == 0) return (0, 0);

        Allocation memory _allocation;
        address _strategy;
        uint256 _currentDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _allocation = _newAllocations[i];
            _strategy = _allocation.strategy;
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;
            uint256 _strategyApr = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            _currentApr += _strategyApr;
            if (_currentDebt == uint256(int256(_allocation.newDebt))) {
                _expectedApr += _strategyApr;
            } else {
                _expectedApr += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_allocation.newDebt) - int256(_currentDebt)
                ) * uint256(int256(_allocation.newDebt)));
            }
        }

        _currentApr /= _totalAssets;
        _expectedApr /= _totalAssets;
    }

    function _allocate(
        address _vault,
        Allocation[] memory _newAllocations
    ) internal {
        Allocation memory _allocation;
        uint256 _newDebt;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _allocation = _newAllocations[i];
            _newDebt = uint256(int256(_allocation.newDebt));

            uint256 _currentDebt = IVault(_vault)
                .strategies(_allocation.strategy)
                .current_debt;

            if (_newDebt == _currentDebt) continue;

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

            IVault(_vault).update_debt(_allocation.strategy, _newDebt);
        }
    }
}
