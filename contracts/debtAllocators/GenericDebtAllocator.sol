// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

/**
 * @title YearnV3 Generic Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Generic Debt Allocator is meant to be used alongside
 *  a Yearn V3 vault to provide the needed triggers for a keeper
 *  to perform automated debt updates for the vaults strategies.
 *
 *  Each allocator contract will serve one Vault and each strategy
 *  that should be managed by this allocator will need to be added
 *  manually by setting a `targetRatio` and `maxRatio`.
 *
 *  The allocator aims to allocate debt between the strategies
 *  based on their set target ratios. Which are denominated in basis
 *  points and represent the percent of total assets that specific
 *  strategy should hold.
 *
 *  The trigger will attempt to allocate up to the `maxRatio` when
 *  the strategy has `minimumChange` amount less than the `targetRatio`.
 *  And will pull funds from the strategy when it has `minimumChange`
 *  more than its `maxRatio`.
 */
contract GenericDebtAllocator is Governance {
    /// @notice An event emitted when a strategies debt ratios are Updated.
    event UpdateStrategyDebtRatios(
        address indexed strategy,
        uint256 newTargetRatio,
        uint256 newMaxRatio,
        uint256 newTotalDebtRatio
    );

    /// @notice An event emitted when the minimum change is updated.
    event UpdateMinimumChange(uint256 newMinimumChange);

    /// @notice An event emitted when the max base fee is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    /// @notice An event emitted when the max debt update loss is updated.
    event UpdateMaxDebtUpdateLoss(uint256 newMaxDebtUpdateLoss);

    /// @notice An event emitted when the minimum time to wait is updated.
    event UpdateMinimumWait(uint256 newMinimumWait);

    /// @notice Struct for each strategies info.
    struct Config {
        // The ideal percent in Basis Points the strategy should have.
        uint256 targetRatio;
        // The max percent of assets the strategy should hold.
        uint256 maxRatio;
        // Timestamp of the last time debt was updated.
        // The debt updates must be done through this allocator
        // for this to be used.
        uint256 lastUpdate;
    }

    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Vaults DEBT_MANAGER enumerator.
    uint256 internal constant DEBT_MANAGER = 64;

    /// @notice Mapping of strategy => its config.
    mapping(address => Config) public configs;

    /// @notice Address of the vault this serves as allocator for.
    address public vault;

    /// @notice Total debt ratio currently allocated in basis points.
    // Can't be more than 10_000.
    uint256 public debtRatio;

    /// @notice The minimum amount denominated in asset that will
    // need to be moved to trigger a debt update.
    uint256 public minimumChange;

    /// @notice Time to wait between debt updates.
    uint256 public minimumWait;

    /// @notice Max loss to accept on debt updates in basis points.
    uint256 public maxDebtUpdateLoss;

    /// @notice Max the chains base fee can be during debt update.
    // Will default to max uint256 and need to be set to be used.
    uint256 public maxAcceptableBaseFee;

    constructor(
        address _vault,
        address _governance,
        uint256 _minimumChange
    ) Governance(_governance) {
        initialize(_vault, _governance, _minimumChange);
    }

    /**
     * @notice Initializes the debt allocator.
     * @dev Should be called atomically after cloning.
     * @param _vault Address of the vault this allocates debt for.
     * @param _governance Address to govern this contract.
     * @param _minimumChange The minimum in asset that must be moved.
     */
    function initialize(
        address _vault,
        address _governance,
        uint256 _minimumChange
    ) public virtual {
        require(address(vault) == address(0), "!initialized");
        vault = _vault;
        governance = _governance;
        minimumChange = _minimumChange;
        // Default max base fee to uint256 max
        maxAcceptableBaseFee = type(uint256).max;
        // Default max loss on debt updates to 1 BP.
        maxDebtUpdateLoss = 1;
    }

    /**
     * @notice Debt update wrapper for the vault.
     * @dev This can be used if a minimum time between debt updates
     *   is desired to be enforced and to enforce a max loss.
     *
     *   This contract and the msg.sender must have the DEBT_MANAGER
     *   role assigned to them.
     *
     *   The function signature matches the vault so no update to the
     *   call data is required.
     *
     *   This will also run checks on losses realized during debt
     *   updates to assure decreases did not realize profits outside
     *   of the allowed range.
     */
    function update_debt(
        address _strategy,
        uint256 _targetDebt
    ) external virtual {
        IVault _vault = IVault(vault);
        require(
            (_vault.roles(msg.sender) & DEBT_MANAGER) == DEBT_MANAGER,
            "not allowed"
        );

        // Cache initial values in case of loss.
        uint256 initialDebt = _vault.strategies(_strategy).current_debt;
        uint256 initialAssets = _vault.totalAssets();
        _vault.update_debt(_strategy, _targetDebt);
        uint256 afterAssets = _vault.totalAssets();

        // If a loss was realized.
        if (afterAssets < initialAssets) {
            // Make sure its within the range.
            require(
                initialAssets - afterAssets <=
                    (initialDebt * maxDebtUpdateLoss) / MAX_BPS,
                "too much loss"
            );
        }

        // Update the last time the strategies debt was updated.
        configs[_strategy].lastUpdate = block.timestamp;
    }

    /**
     * @notice Check if a strategy's debt should be updated.
     * @dev This should be called by a keeper to decide if a strategies
     * debt should be updated and if so by how much.
     *
     * NOTE: This cannot be used to withdraw down to 0 debt.
     *
     * @param _strategy Address of the strategy to check.
     * @return . Bool representing if the debt should be updated.
     * @return . Calldata if `true` or reason if `false`.
     */
    function shouldUpdateDebt(
        address _strategy
    ) external view virtual returns (bool, bytes memory) {
        // Check the base fee isn't too high.
        if (block.basefee > maxAcceptableBaseFee) {
            return (false, bytes("Base Fee"));
        }

        // Cache the vault variable.
        IVault _vault = IVault(vault);
        // Retrieve the strategy specific parameters.
        IVault.StrategyParams memory params = _vault.strategies(_strategy);
        // Make sure its an active strategy.
        require(params.activation != 0, "!active");

        // Get the strategy specific debt config.
        Config memory config = configs[_strategy];
        // Make sure we have a target debt.
        require(config.targetRatio != 0, "no targetRatio");

        if (block.timestamp - config.lastUpdate <= minimumWait) {
            return (false, bytes("min wait"));
        }

        uint256 vaultAssets = _vault.totalAssets();

        // Get the target debt for the strategy based on vault assets.
        uint256 targetDebt = Math.min(
            (vaultAssets * config.targetRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // Get the max debt we would want the strategy to have.
        uint256 maxDebt = Math.min(
            (vaultAssets * config.maxRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // If we need to add more.
        if (targetDebt > params.current_debt) {
            uint256 currentIdle = _vault.totalIdle();
            uint256 minIdle = _vault.minimum_total_idle();

            // We can't add more than the available idle.
            if (minIdle >= currentIdle) {
                return (false, bytes("No Idle"));
            }

            // Add up to the max if possible
            uint256 toAdd = Math.min(
                maxDebt - params.current_debt,
                // Can't take more than is available.
                Math.min(
                    currentIdle - minIdle,
                    IVault(_strategy).maxDeposit(vault)
                )
            );

            // If the amount to add is over our threshold.
            if (toAdd > minimumChange) {
                // Return true and the calldata.
                return (
                    true,
                    abi.encodeCall(
                        _vault.update_debt,
                        (_strategy, params.current_debt + toAdd)
                    )
                );
            }
            // If current debt is greater than our max.
        } else if (maxDebt < params.current_debt) {
            // Find out by how much. Aim for the target.
            uint256 toPull = Math.min(
                params.current_debt - targetDebt,
                // Account for the current liquidity constraints.
                // Use max redeem to match vault logic.
                IVault(_strategy).convertToAssets(
                    IVault(_strategy).maxRedeem(address(_vault))
                )
            );

            // Check if it's over the threshold.
            if (toPull > minimumChange) {
                // Can't lower debt if there is unrealised losses.
                if (
                    _vault.assess_share_of_unrealised_losses(
                        _strategy,
                        params.current_debt
                    ) != 0
                ) {
                    return (false, bytes("unrealised loss"));
                }

                // If so return true and the calldata.
                return (
                    true,
                    abi.encodeCall(
                        _vault.update_debt,
                        (_strategy, params.current_debt - toPull)
                    )
                );
            }
        }

        // Either no change or below our minimumChange.
        return (false, bytes("Below Min"));
    }

    /**
     * @notice Sets a new target debt ratio for a strategy.
     * @dev A `minimumChange` for that strategy must be set first.
     * This is to prevent debt from being updated too frequently.
     *
     * @param _strategy Address of the strategy to set.
     * @param _targetRatio Amount in Basis points to allocate.
     * @param _maxRatio Max ratio to give on debt increases.
     */
    function setStrategyDebtRatios(
        address _strategy,
        uint256 _targetRatio,
        uint256 _maxRatio
    ) external virtual onlyGovernance {
        // Make sure a minimumChange has been set.
        require(minimumChange != 0, "!minimum");
        // Cannot be more than 100%.
        require(_maxRatio <= MAX_BPS, "max too high");
        // Max cannot be lower than the target.
        require(_maxRatio >= _targetRatio, "max ratio");

        // Get what will be the new total debt ratio.
        uint256 newDebtRatio = debtRatio -
            configs[_strategy].targetRatio +
            _targetRatio;

        // Make sure it is under 100% allocated
        require(newDebtRatio <= MAX_BPS, "ratio too high");

        // Write to storage.
        configs[_strategy].targetRatio = _targetRatio;
        configs[_strategy].maxRatio = _maxRatio;

        debtRatio = newDebtRatio;

        emit UpdateStrategyDebtRatios(
            _strategy,
            _targetRatio,
            _maxRatio,
            newDebtRatio
        );
    }

    /**
     * @notice Set the minimum change variable for a strategy.
     * @dev This is the amount of debt that will needed to be
     * added or pulled for it to trigger an update.
     *
     * @param _minimumChange The new minimum to set for the strategy.
     */
    function setMinimumChange(
        uint256 _minimumChange
    ) external virtual onlyGovernance {
        require(_minimumChange > 0, "zero");
        // Set the new minimum.
        minimumChange = _minimumChange;

        emit UpdateMinimumChange(_minimumChange);
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

    /**
     * @notice Set the minimum time to wait before re-updating a strategies debt.
     * @dev This is only enforced per strategy.
     * @param _minimumWait The minimum time in seconds to wait.
     */
    function setMinimumWait(
        uint256 _minimumWait
    ) external virtual onlyGovernance {
        minimumWait = _minimumWait;

        emit UpdateMinimumWait(_minimumWait);
    }

    /**
     * @notice Set the max acceptable base fee.
     * @dev This defaults to max uint256 and will need to
     * be set for it to be used.
     *
     * Is denominated in gwei. So 50gwei would be set as 50e9.
     *
     * @param _maxAcceptableBaseFee The new max base fee.
     */
    function setMaxAcceptableBaseFee(
        uint256 _maxAcceptableBaseFee
    ) external virtual onlyGovernance {
        maxAcceptableBaseFee = _maxAcceptableBaseFee;

        emit UpdateMaxAcceptableBaseFee(_maxAcceptableBaseFee);
    }
}
