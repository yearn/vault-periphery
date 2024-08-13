// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

/**
 * @title YearnV3  Debt Allocator
 * @author yearn.finance
 * @notice
 *  This Debt Allocator is meant to be used alongside
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
contract DebtAllocator is Governance {
    /// @notice An event emitted when the base fee provider is set.
    event UpdatedBaseFeeProvider(address baseFeeProvider);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice An event emitted when the max base fee is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    /// @notice An event emitted when a strategies debt ratios are Updated.
    event UpdateStrategyDebtRatio(
        address indexed vault,
        address indexed strategy,
        uint256 newTargetRatio,
        uint256 newMaxRatio,
        uint256 newTotalDebtRatio
    );

    /// @notice An event emitted when a strategy is added or removed.
    event StrategyChanged(
        address indexed vault,
        address indexed strategy,
        Status status
    );

    /// @notice An event emitted when the minimum time to wait is updated.
    event UpdateMinimumWait(address indexed vault, uint256 newMinimumWait);

    /// @notice An event emitted when the minimum change is updated.
    event UpdateMinimumChange(address indexed vault, uint256 newMinimumChange);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateManager(
        address indexed vault,
        address indexed manager,
        bool allowed
    );

    /// @notice An event emitted when the max debt update loss is updated.
    event UpdateMaxDebtUpdateLoss(
        address indexed vault,
        uint256 newMaxDebtUpdateLoss
    );

    /// @notice Status when a strategy is added or removed from the allocator.
    enum Status {
        NULL,
        ADDED,
        REMOVED
    }

    /// @notice Struct for each strategies info.
    struct StrategyConfig {
        // Flag to set when a strategy is added.
        bool added;
        // The ideal percent in Basis Points the strategy should have.
        uint16 targetRatio;
        // The max percent of assets the strategy should hold.
        uint16 maxRatio;
        // Timestamp of the last time debt was updated.
        // The debt updates must be done through this allocator
        // for this to be used.
        uint96 lastUpdate;
        // We have an extra 120 bits in the slot.
        // So we declare the variable in the struct so it can be
        // used if this contract is inherited.
        uint120 open;
    }

    struct VaultConfig {
        uint256 minimumWait;
        uint256 minimumChange;
        uint256 totalDebtRatio;
        uint256 maxDebtUpdateLoss;
        mapping(address => bool) managers;
    }

    /// @notice Make sure the caller is governance or a manager.
    modifier onlyManagers(address _vault) {
        _isManager(_vault);
        _;
    }

    /// @notice Make sure the caller is a keeper
    modifier onlyKeepers() {
        _isKeeper();
        _;
    }

    /// @notice Check is either factories governance or local manager.
    function _isManager(address _vault) internal view virtual {
        require(
            getVaultConfig(_vault).managers[msg.sender] ||
                msg.sender == governance,
            "!manager"
        );
    }

    /// @notice Check is one of the allowed keepers.
    function _isKeeper() internal view virtual {
        require(keepers[msg.sender], "!keeper");
    }

    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Provider to read current block's base fee.
    address public baseFeeProvider;

    /// @notice Max the chains base fee can be during debt update.
    // Will default to max uint256 and need to be set to be used.
    uint256 public maxAcceptableBaseFee;

    /// @notice Mapping of addresses that are allowed to update debt.
    mapping(address => bool) public keepers;

    mapping(address => VaultConfig) internal _vaultConfigs;

    /// @notice Mapping of strategy => its config.
    mapping(address => mapping(address => StrategyConfig))
        internal _strategyConfigs;

    constructor(address _governance) Governance(_governance) {
        // Default max base fee to uint max.
        maxAcceptableBaseFee = type(uint256).max;

        // Default to allow governance to be a keeper.
        keepers[_governance] = true;
        emit UpdateKeeper(_governance, true);
    }

    /**
     * @notice Debt update wrapper for the vault.
     * @dev This can be used if a minimum time between debt updates
     *   is desired to be used for the trigger and to enforce a max loss.
     *
     *   This contract must have the DEBT_MANAGER role assigned to them.
     *
     *   The function signature matches the vault so no update to the
     *   call data is required.
     *
     *   This will also run checks on losses realized during debt
     *   updates to assure decreases did not realize profits outside
     *   of the allowed range.
     */
    function update_debt(
        address _vault,
        address _strategy,
        uint256 _targetDebt
    ) public virtual onlyKeepers {
        IVault vault = IVault(_vault);

        // If going to 0 record full balance first.
        if (_targetDebt == 0) {
            vault.process_report(_strategy);
        }

        // Update debt with the default max loss.
        vault.update_debt(
            _strategy,
            _targetDebt,
            getVaultConfig(_vault).maxDebtUpdateLoss
        );

        // Update the last time the strategies debt was updated.
        _strategyConfigs[_vault][_strategy].lastUpdate = uint96(
            block.timestamp
        );
    }

    /**
     * @notice Check if a strategy's debt should be updated.
     * @dev This should be called by a keeper to decide if a strategies
     * debt should be updated and if so by how much.
     *
     * @param _strategy Address of the strategy to check.
     * @return . Bool representing if the debt should be updated.
     * @return . Calldata if `true` or reason if `false`.
     */
    function shouldUpdateDebt(
        address _vault,
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        // Get the strategy specific debt config.
        StrategyConfig memory strategyConfig = getStrategyConfig(
            _vault,
            _strategy
        );
        VaultConfig memory vaultConfig = getVaultConfig(_vault);

        // Make sure the strategy has been added to the allocator.
        if (!strategyConfig.added) return (false, bytes("!added"));

        // Check the base fee isn't too high.
        if (!isCurrentBaseFeeAcceptable()) {
            return (false, bytes("Base Fee"));
        }

        // Cache the vault variable.
        IVault vault = IVault(_vault);
        // Retrieve the strategy specific parameters.
        IVault.StrategyParams memory params = vault.strategies(_strategy);
        // Make sure its an active strategy.
        require(params.activation != 0, "!active");

        if (
            block.timestamp - strategyConfig.lastUpdate <=
            vaultConfig.minimumWait
        ) {
            return (false, bytes("min wait"));
        }

        uint256 vaultAssets = vault.totalAssets();

        // Get the target debt for the strategy based on vault assets.
        uint256 targetDebt = Math.min(
            (vaultAssets * strategyConfig.targetRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // Get the max debt we would want the strategy to have.
        uint256 maxDebt = Math.min(
            (vaultAssets * strategyConfig.maxRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // If we need to add more.
        if (targetDebt > params.current_debt) {
            uint256 currentIdle = vault.totalIdle();
            uint256 minIdle = vault.minimum_total_idle();

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
                    IVault(_strategy).maxDeposit(_vault)
                )
            );

            // If the amount to add is over our threshold.
            if (toAdd > vaultConfig.minimumChange) {
                // Return true and the calldata.
                return (
                    true,
                    abi.encodeWithSignature(
                        "update_debt(address,uint256)",
                        _strategy,
                        params.current_debt + toAdd
                    )
                );
            }
            // If current debt is greater than our max.
        } else if (maxDebt < params.current_debt) {
            uint256 toPull = params.current_debt - targetDebt;

            uint256 currentIdle = vault.totalIdle();
            uint256 minIdle = vault.minimum_total_idle();
            if (minIdle > currentIdle) {
                // Pull at least the amount needed for minIdle.
                toPull = Math.max(toPull, minIdle - currentIdle);
            }

            // Find out by how much. Aim for the target.
            toPull = Math.min(
                toPull,
                // Account for the current liquidity constraints.
                // Use max redeem to match vault logic.
                IVault(_strategy).convertToAssets(
                    IVault(_strategy).maxRedeem(address(vault))
                )
            );

            // Check if it's over the threshold.
            if (toPull > vaultConfig.minimumChange) {
                // Can't lower debt if there are unrealised losses.
                if (
                    vault.assess_share_of_unrealised_losses(
                        _strategy,
                        params.current_debt
                    ) != 0
                ) {
                    return (false, bytes("unrealised loss"));
                }

                // If so return true and the calldata.
                return (
                    true,
                    abi.encodeWithSignature(
                        "update_debt(address,uint256)",
                        _strategy,
                        params.current_debt - toPull
                    )
                );
            }
        }

        // Either no change or below our minimumChange.
        return (false, bytes("Below Min"));
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increase a strategies target debt ratio.
     * @dev `setStrategyDebtRatio` functions will do all needed checks.
     * @param _strategy The address of the strategy to increase the debt ratio for.
     * @param _increase The amount in Basis Points to increase it.
     */
    function increaseStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _increase
    ) external virtual {
        uint256 _currentRatio = getStrategyConfig(_vault, _strategy)
            .targetRatio;
        setStrategyDebtRatio(_strategy, _currentRatio + _increase);
    }

    /**
     * @notice Decrease a strategies target debt ratio.
     * @param _strategy The address of the strategy to decrease the debt ratio for.
     * @param _decrease The amount in Basis Points to decrease it.
     */
    function decreaseStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _decrease
    ) external virtual {
        uint256 _currentRatio = getStrategyConfig(_vault, _strategy)
            .targetRatio;
        setStrategyDebtRatio(_strategy, _currentRatio - _decrease);
    }

    /**
     * @notice Sets a new target debt ratio for a strategy.
     * @dev This will default to a 20% increase for max debt.
     *
     * @param _strategy Address of the strategy to set.
     * @param _targetRatio Amount in Basis points to allocate.
     */
    function setStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _targetRatio
    ) public virtual {
        uint256 maxRatio = Math.min((_targetRatio * 12_000) / MAX_BPS, MAX_BPS);
        setStrategyDebtRatio(_strategy, _targetRatio, maxRatio);
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
    function setStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _targetRatio,
        uint256 _maxRatio
    ) public virtual onlyManagers(_vault) {
        VaultConfig storage vaultConfig = getVaultConfig(_vault);
        // Make sure a minimumChange has been set.
        require(vaultConfig.minimumChange != 0, "!minimum");
        // Cannot be more than 100%.
        require(_maxRatio <= MAX_BPS, "max too high");
        // Max cannot be lower than the target.
        require(_maxRatio >= _targetRatio, "max ratio");

        // Get the current config.
        StrategyConfig memory strategyConfig = getStrategyConfig(
            _vault,
            _strategy
        );

        // Set added flag if not set yet.
        if (!strategyConfig.added) {
            strategyConfig.added = true;
            emit StrategyChanged(_vault, _strategy, Status.ADDED);
        }

        // Get what will be the new total debt ratio.
        uint256 newTotalDebtRatio = vaultConfig.totalDebtRatio -
            strategyConfig.targetRatio +
            _targetRatio;

        // Make sure it is under 100% allocated
        require(newTotalDebtRatio <= MAX_BPS, "ratio too high");

        // Update local config.
        strategyConfig.targetRatio = uint16(_targetRatio);
        strategyConfig.maxRatio = uint16(_maxRatio);

        // Write to storage.
        _strategyConfigs[_vault][_strategy] = strategyConfig;
        vaultConfig.totalDebtRatio = newTotalDebtRatio;

        emit UpdateStrategyDebtRatio(
            _vault,
            _strategy,
            _targetRatio,
            _maxRatio,
            newTotalDebtRatio
        );
    }

    /**
     * @notice Remove a strategy from this debt allocator.
     * @dev Will delete the full config for the strategy
     * @param _strategy Address of the address ro remove.
     */
    function removeStrategy(
        address _vault,
        address _strategy
    ) external virtual onlyManagers(_vault) {
        StrategyConfig memory strategyConfig = getStrategyConfig(
            _vault,
            _strategy
        );
        require(strategyConfig.added, "!added");

        uint256 target = strategyConfig.targetRatio;

        // Remove any debt ratio the strategy holds.
        if (target != 0) {
            uint256 newRatio = _vaultConfigs[_vault].totalDebtRatio - target;
            _vaultConfigs[_vault].totalDebtRatio = newRatio;
            emit UpdateStrategyDebtRatio(_strategy, 0, 0, newRatio);
        }

        // Remove the full config including the `added` flag.
        delete _strategyConfigs[_vault][_strategy];

        // Emit Event.
        emit StrategyChanged(_vault, _strategy, Status.REMOVED);
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the minimum change variable for a strategy.
     * @dev This is the minimum amount of debt to be
     * added or pulled for it to trigger an update.
     *
     * @param _minimumChange The new minimum to set for the strategy.
     */
    function setMinimumChange(
        address _vault,
        uint256 _minimumChange
    ) external virtual onlyGovernance {
        require(_minimumChange > 0, "zero");
        // Set the new minimum.
        _vaultConfigs[_vault].minimumChange = _minimumChange;

        emit UpdateMinimumChange(_vault, _minimumChange);
    }

    /**
     * @notice Set the max loss in Basis points to allow on debt updates.
     * @dev Withdrawing during debt updates use {redeem} which allows for 100% loss.
     *      This can be used to assure a loss is not realized on redeem outside the tolerance.
     * @param _maxDebtUpdateLoss The max loss to accept on debt updates.
     */
    function setMaxDebtUpdateLoss(
        address _vault,
        uint256 _maxDebtUpdateLoss
    ) external virtual onlyGovernance {
        require(_maxDebtUpdateLoss <= MAX_BPS, "higher than max");
        _vaultConfigs[_vault].maxDebtUpdateLoss = _maxDebtUpdateLoss;

        emit UpdateMaxDebtUpdateLoss(_vault, _maxDebtUpdateLoss);
    }

    /**
     * @notice Set the minimum time to wait before re-updating a strategies debt.
     * @dev This is only enforced per strategy.
     * @param _minimumWait The minimum time in seconds to wait.
     */
    function setMinimumWait(
        address _vault,
        uint256 _minimumWait
    ) external virtual onlyGovernance {
        _vaultConfigs[_vault].minimumWait = _minimumWait;

        emit UpdateMinimumWait(_vault, _minimumWait);
    }

    /**
     * @notice Set if a manager can update ratios.
     * @param _address The address to set mapping for.
     * @param _allowed If the address can call {update_debt}.
     */
    function setManager(
        address _vault,
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        _vaultConfigs[_vault].managers[_address] = _allowed;

        emit UpdateManager(_vault, _address, _allowed);
    }

    /**
     * @notice
     *  Used to set our baseFeeProvider, which checks the network's current base
     *  fee price to determine whether it is an optimal time to harvest or tend.
     *
     *  This may only be called by governance.
     * @param _baseFeeProvider Address of our baseFeeProvider
     */
    function setBaseFeeOracle(
        address _baseFeeProvider
    ) external virtual onlyGovernance {
        baseFeeProvider = _baseFeeProvider;

        emit UpdatedBaseFeeProvider(_baseFeeProvider);
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

    /**
     * @notice Get a strategies full config.
     * @dev Used for customizations by inheriting the contract.
     * @param _strategy Address of the strategy.
     * @return The strategies current Config.
     */
    function getStrategyConfig(
        address _vault,
        address _strategy
    ) public view virtual returns (StrategyConfig memory) {
        return _strategyConfigs[_vault][_strategy];
    }

    /**
     * @notice Get a vaults full config.
     * @dev Used for customizations by inheriting the contract.
     * @param _vault Address of the vault.
     * @return The vaults current Config.
     */
    function getVaultConfig(
        address _vault
    ) public view virtual returns (VaultConfig memory) {
        return _vaultConfigs[_vault];
    }

    /**
     * @notice Get a strategies target debt ratio.
     * @param _strategy Address of the strategy.
     * @return The strategies current targetRatio.
     */
    function getStrategyTargetRatio(
        address _vault,
        address _strategy
    ) external view virtual returns (uint256) {
        return getStrategyConfig(_vault, _strategy).targetRatio;
    }

    /**
     * @notice Get a strategies max debt ratio.
     * @param _strategy Address of the strategy.
     * @return The strategies current maxRatio.
     */
    function getStrategyMaxRatio(
        address _vault,
        address _strategy
    ) external view virtual returns (uint256) {
        return getStrategyConfig(_vault, _strategy).maxRatio;
    }

    /**
     * @notice Returns wether or not the current base fee is acceptable
     *   based on the `maxAcceptableBaseFee`.
     * @return . If the current base fee is acceptable.
     */
    function isCurrentBaseFeeAcceptable() public view virtual returns (bool) {
        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider == address(0)) return true;
        return
            maxAcceptableBaseFee >= IBaseFee(_baseFeeProvider).basefee_global();
    }
}
