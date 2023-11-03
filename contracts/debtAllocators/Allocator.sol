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
 *  manually by setting a `minimumChange` and a `targetRatio`.
 *
 *  The allocator aims to allocate debt between the strategies
 *  based on their set target ratios. Which are denominated in basis
 *  points and represent the percent of total assets that specific
 *  strategy should hold.
 */
contract GenericDebtAllocator is Governance {
    event SetTargetDebtRatio(
        address indexed strategy,
        uint256 targetRatio,
        uint256 totalDebtRatio
    );

    event SetMinimumChange(uint256 minimumChange);

    event SetMaxAcceptableBaseFee(uint256 maxAcceptableBaseFee);

    event SetMinWait(uint256 newMinWait);

    // Struct for each strategies info.
    struct Config {
        // The percent in Basis Points the strategy should have.
        uint256 targetRatio;
        uint256 maxRatio;
        uint256 lastUpdate;
    }

    uint256 internal constant MAX_BPS = 10_000;

    // Mapping of strategy => its config.
    mapping(address => Config) public configs;

    address public keeper;

    // Address of the vault this serves as allocator for.
    address public vault;

    // Total debt ratio currently allocated in basis points.
    // Can't be more than 10_000.
    uint256 public debtRatio;

    // The minimum amount denominated in asset that will
    // need to be moved to trigger a debt update.
    uint256 public minimumChange;

    // Max the chains base fee can be during debt update.
    // Will default to max uint256 and need to be set to be used.
    uint256 public maxAcceptableBaseFee;

    uint256 public minWait;

    constructor(address _vault, address _governance) Governance(_governance) {
        initialize(_vault, _governance);
    }

    /**
     * @notice Initializes the debt allocator.
     * @dev Should be called atomically after cloning.
     * @param _vault Address of the vault this allocates debt for.
     * @param _governance Address to govern this contract.
     */
    function initialize(address _vault, address _governance) public {
        require(address(vault) == address(0), "!initialized");
        vault = _vault;
        governance = _governance;
        // Default max base fee to uint256 max
        maxAcceptableBaseFee = type(uint256).max;
    }

    function update_debt(address _strategy, uint256 _targetDebt) external {
        require(msg.sender == keeper, "!keeper");
        IVault(vault).update_debt(_strategy, _targetDebt);
        configs[_strategy].lastUpdate = block.timestamp;
    }

    /**
     * @notice Check if a strategy's debt should be updated.
     * @dev This should be called by a keeper to decide if a strategies
     * debt should be updated and if so by how much.
     *
     * This cannot be used to withdraw down to 0 debt.
     *
     * @param _strategy Address of the strategy to check.
     * @return . Bool representing if the debt should be updated.
     * @return . Calldata if `true` or reason if `false`.
     */
    function shouldUpdateDebt(
        address _strategy
    ) external view returns (bool, bytes memory) {
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

        if (block.timestamp - config.lastUpdate <= minWait) {
            return (false, "min wait");
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
            // If target debt is lower than the current.
        } else if (maxDebt < params.current_debt) {
            // Find out by how much.
            uint256 toPull = Math.min(
                params.current_debt - targetDebt,
                // Account for the current liquidity constraints.
                IVault(_strategy).maxWithdraw(address(_vault))
            );

            // Check if it's over the threshold.
            if (toPull > minimumChange) {
                // Can't lower debt if there is unrealised losses.
                if (
                    _vault.assess_share_of_unrealised_losses(
                        _strategy,
                        params.current_debt
                    ) > 0
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
    ) external onlyGovernance {
        // Make sure the strategy is added to the vault.
        require(IVault(vault).strategies(_strategy).activation != 0, "!active");
        // Make sure a minimumChange has been set.
        require(minimumChange != 0, "!minimum");
        // Max can not be lower than the target.
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

        emit SetTargetDebtRatio(_strategy, _targetRatio, newDebtRatio);
    }

    /**
     * @notice Set the minimum change variable for a strategy.
     * @dev This is the amount of debt that will needed to be
     * added or pulled for it to trigger an update.
     *
     * @param _minimumChange The new minimum to set for the strategy.
     */
    function setMinimumChange(uint256 _minimumChange) external onlyGovernance {
        require(minimumChange > 0, "zero");
        // Set the new minimum.
        minimumChange = _minimumChange;

        emit SetMinimumChange(_minimumChange);
    }

    function setKeeper(address _keeper) external onlyGovernance {
        keeper = _keeper;
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
    ) external onlyGovernance {
        maxAcceptableBaseFee = _maxAcceptableBaseFee;

        emit SetMaxAcceptableBaseFee(_maxAcceptableBaseFee);
    }

    /**
     * @notice Set the max acceptable base fee.
     * @dev This defaults to max uint256 and will need to
     * be set for it to be used.
     *
     * Is denominated in gwei. So 50gwei would be set as 50e9.
     *
     * @param _minWait The new max base fee.
     */
    function setMinTime(uint256 _minWait) external onlyGovernance {
        minWait = _minWait;

        emit SetMinWait(_minWait);
    }
}
