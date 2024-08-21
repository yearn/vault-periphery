// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
 *  Each vault that should be managed by this allocator will
 *  need to be added by first setting a `minimumChange` for the
 *  vault, which will act as the amount of funds to move that will
 *  trigger a debt update. Then adding each strategy by setting a
 *  `targetRatio` and `maxRatio`.
 *
 *  The allocator aims to allocate debt between the strategies
 *  based on their set target ratios. Which are denominated in basis
 *  points and represent the percent of total assets that specific
 *  strategy should hold.
 *
 *  The trigger will attempt to allocate up to the `maxRatio` when
 *  the strategy has `minimumChange` amount less than the `targetRatio`.
 *  And will pull funds to the `targetRatio` when it has `minimumChange`
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

    /// @notice An event emitted when the minimum change is updated.
    event UpdateMinimumChange(address indexed vault, uint256 newMinimumChange);

    /// @notice An even emitted when the paused status is updated.
    event UpdatePaused(address indexed vault, bool indexed status);

    /// @notice An event emitted when the minimum time to wait is updated.
    event UpdateMinimumWait(uint256 newMinimumWait);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateManager(address indexed manager, bool allowed);

    /// @notice An event emitted when the max debt update loss is updated.
    event UpdateMaxDebtUpdateLoss(uint256 newMaxDebtUpdateLoss);

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

    /// @notice Struct to hold the vault's info.
    struct VaultConfig {
        // Optional flag to stop the triggers.
        bool paused;
        // The minimum amount denominated in asset that will
        // need to be moved to trigger a debt update.
        uint128 minimumChange;
        // Total debt ratio currently allocated in basis points.
        // Can't be more than 10_000.
        uint16 totalDebtRatio;
    }

    /// @notice Used during the `shouldUpdateDebt` to hold the data.
    struct StrategyDebtInfo {
        VaultConfig vaultConfig;
        StrategyConfig strategyConfig;
        uint256 vaultAssets;
        uint256 targetDebt;
        uint256 maxDebt;
        uint256 currentIdle;
        uint256 minIdle;
        uint256 max;
        uint256 toChange;
    }

    /// @notice Make sure the caller is governance or a manager.
    modifier onlyManagers() {
        _isManager();
        _;
    }

    /// @notice Make sure the caller is a keeper
    modifier onlyKeepers() {
        _isKeeper();
        _;
    }

    /// @notice Check is either factories governance or local manager.
    function _isManager() internal view virtual {
        require(managers[msg.sender] || msg.sender == governance, "!manager");
    }

    /// @notice Check is one of the allowed keepers.
    function _isKeeper() internal view virtual {
        require(keepers[msg.sender], "!keeper");
    }

    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Time to wait between debt updates in seconds.
    uint256 public minimumWait;

    /// @notice Provider to read current block's base fee.
    address public baseFeeProvider;

    /// @notice Max loss to accept on debt updates in basis points.
    uint256 public maxDebtUpdateLoss;

    /// @notice Max the chains base fee can be during debt update.
    // Will default to max uint256 and need to be set to be used.
    uint256 public maxAcceptableBaseFee;

    /// @notice Mapping of addresses that are allowed to update debt.
    mapping(address => bool) public keepers;

    /// @notice Mapping of addresses that are allowed to update debt ratios.
    mapping(address => bool) public managers;

    mapping(address => VaultConfig) internal _vaultConfigs;

    /// @notice Mapping of vault => strategy => its config.
    mapping(address => mapping(address => StrategyConfig))
        internal _strategyConfigs;

    constructor() Governance(msg.sender) {}

    /**
     * @notice Initialize the contract after being cloned.
     * @dev Sets default values for the global variables.
     */
    function initialize(address _governance) external {
        require(governance == address(0), "initialized");
        require(_governance != address(0), "ZERO ADDRESS");

        governance = _governance;
        emit GovernanceTransferred(address(0), _governance);

        // Default max base fee to uint max.
        maxAcceptableBaseFee = type(uint256).max;

        // Default to allow 1 BP loss.
        maxDebtUpdateLoss = 1;

        // Default minimum wait to 6 hours
        minimumWait = 60 * 60 * 6;

        // Default to allow governance to be a keeper.
        keepers[_governance] = true;
        emit UpdateKeeper(_governance, true);
    }

    /**
     * @notice Debt update wrapper for the vault.
     * @dev This contract must have the DEBT_MANAGER role assigned to them.
     *
     *   This will also uses the `maxUpdateDebtLoss` during debt
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
        vault.update_debt(_strategy, _targetDebt, maxDebtUpdateLoss);

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
     * @param _vault Address of the vault to update.
     * @param _strategy Address of the strategy to check.
     * @return . Bool representing if the debt should be updated.
     * @return . Calldata if `true` or reason if `false`.
     */
    function shouldUpdateDebt(
        address _vault,
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        // Store all local variables in a struct to avoid stack to deep
        StrategyDebtInfo memory strategyDebtInfo;

        strategyDebtInfo.vaultConfig = getVaultConfig(_vault);

        // Don't do anything if paused.
        if (strategyDebtInfo.vaultConfig.paused)
            return (false, bytes("Paused"));

        // Check the base fee isn't too high.
        if (!isCurrentBaseFeeAcceptable()) return (false, bytes("Base Fee"));

        // Get the strategy specific debt config.
        strategyDebtInfo.strategyConfig = getStrategyConfig(_vault, _strategy);

        // Make sure the strategy has been added to the allocator.
        if (!strategyDebtInfo.strategyConfig.added)
            return (false, bytes("!added"));

        if (
            block.timestamp - strategyDebtInfo.strategyConfig.lastUpdate <=
            minimumWait
        ) {
            return (false, bytes("min wait"));
        }

        // Retrieve the strategy specific parameters.
        IVault.StrategyParams memory params = IVault(_vault).strategies(
            _strategy
        );
        // Make sure its an active strategy.
        require(params.activation != 0, "!active");

        strategyDebtInfo.vaultAssets = IVault(_vault).totalAssets();

        // Get the target debt for the strategy based on vault assets.
        strategyDebtInfo.targetDebt = Math.min(
            (strategyDebtInfo.vaultAssets *
                strategyDebtInfo.strategyConfig.targetRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // Get the max debt we would want the strategy to have.
        strategyDebtInfo.maxDebt = Math.min(
            (strategyDebtInfo.vaultAssets *
                strategyDebtInfo.strategyConfig.maxRatio) / MAX_BPS,
            // Make sure it is not more than the max allowed.
            params.max_debt
        );

        // If we need to add more.
        if (strategyDebtInfo.targetDebt > params.current_debt) {
            strategyDebtInfo.currentIdle = IVault(_vault).totalIdle();
            strategyDebtInfo.minIdle = IVault(_vault).minimum_total_idle();
            strategyDebtInfo.max = IVault(_strategy).maxDeposit(_vault);

            // We can't add more than the available idle.
            if (strategyDebtInfo.minIdle >= strategyDebtInfo.currentIdle) {
                return (false, bytes("No Idle"));
            }

            // Add up to the max if possible
            strategyDebtInfo.toChange = Math.min(
                strategyDebtInfo.maxDebt - params.current_debt,
                // Can't take more than is available.
                Math.min(
                    strategyDebtInfo.currentIdle - strategyDebtInfo.minIdle,
                    strategyDebtInfo.max
                )
            );

            // If the amount to add is over our threshold.
            if (
                strategyDebtInfo.toChange >
                strategyDebtInfo.vaultConfig.minimumChange
            ) {
                // Return true and the calldata.
                return (
                    true,
                    abi.encodeCall(
                        this.update_debt,
                        (
                            _vault,
                            _strategy,
                            params.current_debt + strategyDebtInfo.toChange
                        )
                    )
                );
            }
            // If current debt is greater than our max.
        } else if (strategyDebtInfo.maxDebt < params.current_debt) {
            strategyDebtInfo.toChange =
                params.current_debt -
                strategyDebtInfo.targetDebt;

            strategyDebtInfo.currentIdle = IVault(_vault).totalIdle();
            strategyDebtInfo.minIdle = IVault(_vault).minimum_total_idle();
            strategyDebtInfo.max = IVault(_strategy).convertToAssets(
                IVault(_strategy).maxRedeem(_vault)
            );

            if (strategyDebtInfo.minIdle > strategyDebtInfo.currentIdle) {
                // Pull at least the amount needed for minIdle.
                strategyDebtInfo.toChange = Math.max(
                    strategyDebtInfo.toChange,
                    strategyDebtInfo.minIdle - strategyDebtInfo.currentIdle
                );
            }

            // Find out by how much. Aim for the target.
            strategyDebtInfo.toChange = Math.min(
                strategyDebtInfo.toChange,
                // Account for the current liquidity constraints.
                // Use max redeem to match vault logic.
                strategyDebtInfo.max
            );

            // Check if it's over the threshold.
            if (
                strategyDebtInfo.toChange >
                strategyDebtInfo.vaultConfig.minimumChange
            ) {
                // Can't lower debt if there are unrealised losses.
                if (
                    IVault(_vault).assess_share_of_unrealised_losses(
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
                        this.update_debt,
                        (
                            _vault,
                            _strategy,
                            params.current_debt - strategyDebtInfo.toChange
                        )
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
        setStrategyDebtRatio(_vault, _strategy, _currentRatio + _increase);
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
        setStrategyDebtRatio(_vault, _strategy, _currentRatio - _decrease);
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
        setStrategyDebtRatio(_vault, _strategy, _targetRatio, maxRatio);
    }

    /**
     * @notice Sets a new target debt ratio for a strategy.
     * @dev A `minimumChange` for that strategy must be set first.
     * This is to prevent debt from being updated too frequently.
     *
     * @param _vault Address of the vault
     * @param _strategy Address of the strategy to set.
     * @param _targetRatio Amount in Basis points to allocate.
     * @param _maxRatio Max ratio to give on debt increases.
     */
    function setStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _targetRatio,
        uint256 _maxRatio
    ) public virtual onlyManagers {
        VaultConfig storage vaultConfig = _vaultConfigs[_vault];
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
        vaultConfig.totalDebtRatio = uint16(newTotalDebtRatio);

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
     * @param _vault Address of the vault
     * @param _strategy Address of the address ro remove.
     */
    function removeStrategy(
        address _vault,
        address _strategy
    ) external virtual onlyManagers {
        StrategyConfig memory strategyConfig = getStrategyConfig(
            _vault,
            _strategy
        );
        require(strategyConfig.added, "!added");

        uint256 target = strategyConfig.targetRatio;

        // Remove any debt ratio the strategy holds.
        if (target != 0) {
            uint256 newRatio = _vaultConfigs[_vault].totalDebtRatio - target;
            _vaultConfigs[_vault].totalDebtRatio = uint16(newRatio);
            emit UpdateStrategyDebtRatio(_vault, _strategy, 0, 0, newRatio);
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
     * @param _vault Address of the vault
     * @param _minimumChange The new minimum to set for the strategy.
     */
    function setMinimumChange(
        address _vault,
        uint256 _minimumChange
    ) external virtual onlyGovernance {
        require(_minimumChange > 0, "zero");
        // Make sure it fits in the slot size.
        require(_minimumChange < type(uint128).max, "too high");

        // Set the new minimum.
        _vaultConfigs[_vault].minimumChange = uint128(_minimumChange);

        emit UpdateMinimumChange(_vault, _minimumChange);
    }

    /**
     * @notice Allows governance to pause the triggers.
     * @param _vault Address of the vault
     * @param _status Status to set the `paused` bool to.
     */
    function setPaused(
        address _vault,
        bool _status
    ) external virtual onlyGovernance {
        require(_status != _vaultConfigs[_vault].paused, "already set");
        _vaultConfigs[_vault].paused = _status;

        emit UpdatePaused(_vault, _status);
    }

    /*//////////////////////////////////////////////////////////////
                        ALLOCATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

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
     * @notice Set if a manager can update ratios.
     * @param _address The address to set mapping for.
     * @param _allowed If the address can call {update_debt}.
     */
    function setManager(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        managers[_address] = _allowed;

        emit UpdateManager(_address, _allowed);
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
     * @notice
     *  Used to set our baseFeeProvider, which checks the network's current base
     *  fee price to determine whether it is an optimal time to harvest or tend.
     *
     *  This may only be called by governance.
     * @param _baseFeeProvider Address of our baseFeeProvider
     */
    function setBaseFeeProvider(
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
     * @param _vault Address of the vault
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
     * @notice Get a vaults current total debt.
     * @param _vault Address of the vault
     */
    function totalDebtRatio(
        address _vault
    ) external view virtual returns (uint256) {
        return getVaultConfig(_vault).totalDebtRatio;
    }

    /**
     * @notice Get a vaults minimum change required.
     * @param _vault Address of the vault
     */
    function minimumChange(
        address _vault
    ) external view virtual returns (uint256) {
        return getVaultConfig(_vault).minimumChange;
    }

    /**
     * @notice Get the paused status of a vault
     * @param _vault Address of the vault
     */
    function isPaused(address _vault) public view virtual returns (bool) {
        return getVaultConfig(_vault).paused;
    }

    /**
     * @notice Get a strategies target debt ratio.
     * @param _vault Address of the vault
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
     * @param _vault Address of the vault
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
