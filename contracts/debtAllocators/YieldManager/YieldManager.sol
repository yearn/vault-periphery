// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

import {Keeper, Governance} from "./Keeper.sol";
import {DebtAllocator} from "../DebtAllocator.sol";

/**
 * @title YearnV3 Yield Yield Based Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Debt Allocator is meant to be used alongside
 *  a Yearn V3 vault to allocate funds to the optimal strategy.
 */
contract YieldManager is Governance {
    /// @notice Emitted when the open flag is updated.
    event UpdateOpen(bool status);

    /// @notice Emitted when a proposer status is updated.
    event UpdateProposer(address indexed proposer, bool status);

    /// @notice Emitted when a vaults status is updated.
    event UpdateVaultAllocator(address indexed vault, address allocator);

    // Struct that contains the address of the strategy and its best allocation.
    struct Allocation {
        // Address of the strategy.
        address strategy;
        // Debt for the strategy to end with.
        // Can take 79 Billion 18 decimal tokens.
        uint96 newDebt;
    }

    /// @notice Only allow the sender to be an allocator if not opened.
    modifier onlyProposersOrOpen() {
        _isProposerOrOpen();
        _;
    }

    /// @notice Check if it has been opened or is an allocator.
    function _isProposerOrOpen() internal view {
        require(proposer[msg.sender] || open, "!allocator or open");
    }

    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Contract that holds the logic and oracles for each strategy.
    AprOracle internal constant aprOracle =
        AprOracle(0x27aD2fFc74F74Ed27e1C0A19F1858dD0963277aE);

    /// @notice Flag to set to allow anyone to propose allocations.
    bool public open;

    /// @notice Address that should hold the strategies `management` role.
    address public immutable keeper;

    /// @notice Addresses that are allowed to propose allocations.
    mapping(address => bool) public proposer;

    /// @notice Mapping for vaults that can be allocated for => its debt allocator.
    mapping(address => address) public vaultAllocator;

    constructor(address _governance, address _keeper) Governance(_governance) {
        keeper = _keeper;
    }

    /**
     * @notice Update a `_vault`s target allocation of debt.
     * @dev This takes the address of a vault and an array of
     * its strategies and their specific target allocations.
     *
     * The `_newAllocations` array should:
     *   - Contain all strategies that hold any amount of debt from the vault
     *       even if the debt wont be adjusted in order to get the correct
     *       on chain rate.
     *   - Be ordered so that all debt decreases are at the beginning of the array
     *       and debt increases at the end.
     *   - Account for all limiting values such as the vaults max_debt and min_total_idle
     *      as well as the strategies maxDeposit/maxRedeem that are enforced on debt updates.
     *   - Account for the expected differences in amounts caused by unrealised losses or profits.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     * @return _currentRate The current weighted rate that the collective strategies are earning.
     * @return _expectedRate The expected weighted rate that the collective strategies would earn.
     */
    function updateAllocation(
        address _vault,
        Allocation[] memory _newAllocations
    )
        external
        virtual
        onlyProposersOrOpen
        returns (uint256 _currentRate, uint256 _expectedRate)
    {
        address allocator = vaultAllocator[_vault];
        require(allocator != address(0), "vault not added");

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
        uint256 _strategyRate;
        uint256 _targetRatio;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _strategy = _newAllocations[i].strategy;
            _newDebt = uint256(_newAllocations[i].newDebt);
            // Get the debt the strategy current has.
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;
            // Add to what we have accounted for.
            _accountedFor += _currentDebt;

            // Get the current weighted rate the strategy is earning
            _strategyRate = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            // Add to the amount currently being earned.
            _currentRate += _strategyRate;

            // If we are withdrawing.
            if (_currentDebt > _newDebt) {
                // If we are pulling all debt from a strategy.
                if (_newDebt == 0) {
                    // Try to report profits to have them start to unlock.
                    Keeper(keeper).report(_strategy);
                }

                if (
                    // We cannot decrease debt if the strategy has any unrealised losses.
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) != 0
                ) {
                    // Realize the loss.
                    (, uint256 _loss) = IVault(_vault).process_report(
                        _strategy
                    );
                    // Update balances.
                    _currentDebt -= _loss;
                    _totalAssets -= _loss;
                    _accountedFor -= _loss;
                }

                // Make sure we the vault can withdraw that amount.
                require(
                    _maxWithdraw(_vault, _strategy) >= _currentDebt - _newDebt,
                    "max withdraw"
                );
            } else if (_currentDebt < _newDebt) {
                // Make sure the strategy is allowed that much.
                require(
                    IVault(_vault).strategies(_strategy).max_debt >= _newDebt,
                    "max debt"
                );
                // Make sure the vault can deposit the desired amount.
                require(
                    IVault(_strategy).maxDeposit(_vault) >=
                        _newDebt - _currentDebt,
                    "max deposit"
                );
            }

            // Get the target based on the new debt.
            _targetRatio = _newDebt < _totalAssets
                ? (_newDebt * MAX_BPS) / _totalAssets
                : MAX_BPS;

            // If different than the current target.
            if (
                DebtAllocator(allocator).getStrategyTargetRatio(_strategy) !=
                _targetRatio
            ) {
                // Update allocation.
                DebtAllocator(allocator).setStrategyDebtRatio(
                    _strategy,
                    _targetRatio
                );
            }

            // If the new and current debt are the same.
            if (_newDebt == _currentDebt) {
                // We assume the new rate will be the same as current.
                _expectedRate += _strategyRate;
            } else if (_newDebt != 0) {
                _expectedRate += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_newDebt) - int256(_currentDebt) // Debt change.
                ) * _newDebt);
            }
        }

        // Make sure the minimum_total_idle was respected.
        _checkMinimumTotalIdle(_vault, allocator);
        // Make sure the ending amounts are the same otherwise rates could be wrong.
        require(_totalAssets == _accountedFor, "cheater");
        // Make sure we expect to earn more than we currently are.
        require(_expectedRate > _currentRate, "fail");
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
    ) external view virtual returns (bool) {
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
     * @notice Get the current weighted yield rate the vault is earning
     *  and the expected rate based on the proposed changes.
     *
     * Must divide by the totalAssets to get the APR as 1e18.
     *
     * @param _vault The address of the vault to propose an allocation for.
     * @param _newAllocations Array of strategies and their new proposed allocation.
     * @return _currentRate The current weighted rate that the collective strategies are earning.
     * @return _expectedRate The expected weighted rate that the collective strategies would earn.
     */
    function getCurrentAndExpectedRate(
        address _vault,
        Allocation[] memory _newAllocations
    )
        external
        view
        virtual
        returns (uint256 _currentRate, uint256 _expectedRate)
    {
        // Get the total assets the vault has.
        uint256 _totalAssets = IVault(_vault).totalAssets();

        // If 0 nothing to do.
        if (_totalAssets == 0) return (0, 0);

        uint256 _newDebt;
        address _strategy;
        uint256 _currentDebt;
        uint256 _strategyRate;
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _newDebt = uint256(_newAllocations[i].newDebt);
            _strategy = _newAllocations[i].strategy;
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;

            // Get the current weighted rate the strategy is earning
            _strategyRate = (aprOracle.getStrategyApr(_strategy, 0) *
                _currentDebt);

            // Add to the amount currently being earned.
            _currentRate += _strategyRate;

            // If the strategies debt is not changing.
            if (_currentDebt == _newDebt) {
                // No need to call the APR oracle again.
                _expectedRate += _strategyRate;
            } else {
                // We add the expected rate with the new debt.
                _expectedRate += (aprOracle.getStrategyApr(
                    _strategy,
                    int256(_newDebt) - int256(_currentDebt)
                ) * _newDebt);
            }
        }
    }

    /**
     * @notice Update a `_vault`s allocation of debt.
     * @dev This takes the address of a vault and an array of
     * its strategies and their specific allocation.
     *
     * The `_newAllocations` array should:
     *   - Contain all strategies that hold any amount of debt from the vault
     *       even if the debt wont be adjusted in order to get the correct
     *       on chain rate.
     *   - Be ordered so that all debt decreases are at the beginning of the array
     *       and debt increases at the end.
     *   - Account for all limiting values such as the vaults max_debt and min_total_idle
     *      as well as the strategies maxDeposit/maxRedeem that are enforced on debt updates.
     *   - Account for the expected differences in amounts caused by unrealised losses or profits.
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
    ) external virtual onlyGovernance {
        address allocator = vaultAllocator[_vault];
        require(allocator != address(0), "vault not added");
        address _strategy;
        uint256 _newDebt;
        uint256 _currentDebt;
        uint256 _targetRatio;
        uint256 _totalAssets = IVault(_vault).totalAssets();
        for (uint256 i = 0; i < _newAllocations.length; ++i) {
            _strategy = _newAllocations[i].strategy;
            _newDebt = uint256(_newAllocations[i].newDebt);
            // Get the debt the strategy current has.
            _currentDebt = IVault(_vault).strategies(_strategy).current_debt;

            // If we are withdrawing.
            if (_currentDebt > _newDebt) {
                // If we are pulling all debt from a strategy.
                if (_newDebt == 0) {
                    // We need to report profits and have them immediately unlock to not lose out on locked profit.
                    Keeper(keeper).report(_strategy);
                }

                if (
                    // We cannot decrease debt if the strategy has any unrealised losses.
                    IVault(_vault).assess_share_of_unrealised_losses(
                        _strategy,
                        _currentDebt
                    ) != 0
                ) {
                    // Realize the loss.
                    (, uint256 _loss) = IVault(_vault).process_report(
                        _strategy
                    );
                    // Update balances.
                    _currentDebt -= _loss;
                    _totalAssets -= _loss;
                }

                // Make sure we the vault can withdraw that amount.
                require(
                    _maxWithdraw(_vault, _strategy) >= _currentDebt - _newDebt,
                    "max withdraw"
                );
            } else if (_currentDebt < _newDebt) {
                // Make sure the strategy is allowed that much.
                require(
                    IVault(_vault).strategies(_strategy).max_debt >= _newDebt,
                    "max debt"
                );
                // Make sure the vault can deposit the desired amount.
                require(
                    IVault(_strategy).maxDeposit(_vault) >=
                        _newDebt - _currentDebt,
                    "max deposit"
                );
            }

            // Get the target based on the new debt.
            _targetRatio = _newDebt < _totalAssets
                ? (_newDebt * MAX_BPS) / _totalAssets
                : MAX_BPS;

            if (
                DebtAllocator(allocator).getStrategyTargetRatio(_strategy) !=
                _targetRatio
            ) {
                // Update allocation.
                DebtAllocator(allocator).setStrategyDebtRatio(
                    _strategy,
                    _targetRatio
                );
            }
        }
    }

    /**
     * @dev Helper function to get the max a vault can withdraw from a strategy to
     * avoid stack to deep.
     *
     * Uses maxRedeem and convertToAssets since that is what the vault uses.
     */
    function _maxWithdraw(
        address _vault,
        address _strategy
    ) internal view virtual returns (uint256) {
        return
            IVault(_strategy).convertToAssets(
                IVault(_strategy).maxRedeem(_vault)
            );
    }

    /**
     * @dev Helper function to check that the minimum_total_idle of the vault
     * is accounted for in the allocation given.
     *
     * The expected Rate could be wrong if it allocated funds not allowed to be deployed.
     *
     * Use a separate function to avoid stack to deep.
     */
    function _checkMinimumTotalIdle(
        address _vault,
        address _allocator
    ) internal view virtual {
        uint256 totalRatio = DebtAllocator(_allocator).totalDebtRatio();
        uint256 minIdle = IVault(_vault).minimum_total_idle();

        // No need if minIdle is 0.
        if (minIdle != 0) {
            // Make sure we wouldn't allocate more than allowed.
            require(
                // Use 1e18 precision for more exact checks.
                1e18 - (1e14 * totalRatio) >=
                    (minIdle * 1e18) / IVault(_vault).totalAssets(),
                "min idle"
            );
        }
    }

    /**
     * @notice Sets the permission for a proposer.
     * @param _address The address of the proposer.
     * @param _allowed The permission to set for the proposer.
     */
    function setProposer(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        proposer[_address] = _allowed;

        emit UpdateProposer(_address, _allowed);
    }

    /**
     * @notice Sets the mapping of vaults allowed.
     * @param _vault The address of the _vault.
     * @param _allocator The vault specific debt allocator.
     */
    function setVaultAllocator(
        address _vault,
        address _allocator
    ) external virtual onlyGovernance {
        vaultAllocator[_vault] = _allocator;

        emit UpdateVaultAllocator(_vault, _allocator);
    }

    /**
     * @notice Sets the open status of the contract.
     * @param _open The new open status to set.
     */
    function setOpen(bool _open) external virtual onlyGovernance {
        open = _open;

        emit UpdateOpen(_open);
    }
}
