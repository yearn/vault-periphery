// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

contract HealthCheckAccountant {
    using SafeERC20 for ERC20;

    /// @notice An event emitted when a vault is added or removed.
    event VaultChanged(address indexed vault, ChangeType change);

    /// @notice An event emitted when the default fee configuration is updated.
    event UpdateDefaultFeeConfig(Fee defaultFeeConfig);

    /// @notice An event emitted when the future fee manager is set.
    event SetFutureFeeManager(address futureFeeManager);

    /// @notice An event emitted when a new fee manager is accepted.
    event NewFeeManager(address feeManager);

    /// @notice An event emitted when the fee recipient is updated.
    event UpdateFeeRecipient(address oldFeeRecipient, address newFeeRecipient);

    /// @notice An event emitted when a custom fee configuration is updated.
    event UpdateCustomFeeConfig(
        address vault,
        address strategy,
        Fee custom_config
    );

    /// @notice An event emitted when a custom fee configuration is removed.
    event RemovedCustomFeeConfig(
        address indexed vault,
        address indexed strategy
    );

    /// @notice An event emitted when the `maxLoss` parameter is updated.
    event UpdateMaxLoss(uint256 maxLoss);

    /// @notice An event emitted when rewards are distributed.
    event DistributeRewards(address token, uint256 rewards);

    /// @notice Enum defining change types (added or removed).
    enum ChangeType {
        NULL,
        ADDED,
        REMOVED
    }

    /// @notice Struct representing fee details.
    struct Fee {
        uint16 managementFee; // Annual management fee to charge.
        uint16 performanceFee; // Performance fee to charge.
        uint16 refundRatio; // Refund ratio to give back on losses.
        uint16 maxFee; // Max fee allowed as a percent of gain.
        uint16 maxGain; // Max percent gain a strategy can report.
        uint16 maxLoss; // Max percent loss a strategy can report.
    }

    modifier onlyFeeManager() {
        _checkFeeManager();
        _;
    }

    function _checkFeeManager() internal view virtual {
        require(feeManager == msg.sender, "!fee manager");
    }

    /// @notice Constant defining the maximum basis points.
    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Constant defining the number of seconds in a year.
    uint256 internal constant SECS_PER_YEAR = 31_556_952;

    /// @notice Constant defining the performance fee threshold.
    uint16 internal constant PERFORMANCE_FEE_THRESHOLD = 5_000;

    /// @notice Constant defining the management fee threshold.
    uint16 internal constant MANAGEMENT_FEE_THRESHOLD = 200;

    /// @notice The address of the fee manager.
    address public feeManager;

    /// @notice The address of the future fee manager.
    address public futureFeeManager;

    /// @notice The address of the fee recipient.
    address public feeRecipient;

    uint256 public maxLoss;

    /// @notice Mapping to track added vaults.
    mapping(address => bool) public vaults;

    /// @notice The default fee configuration.
    Fee public defaultConfig;

    /// @notice Mapping vault => strategy => custom Fee config if any.
    mapping(address => mapping(address => Fee)) public customConfig;

    /// @notice Mapping vault => strategy => flag to use a custom config.
    mapping(address => mapping(address => uint256)) internal _custom;

    constructor(
        address _feeManager,
        address _feeRecipient,
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) {
        require(_feeManager != address(0), "ZERO ADDRESS");
        require(_feeRecipient != address(0), "ZERO ADDRESS");
        require(
            defaultManagement <= MANAGEMENT_FEE_THRESHOLD,
            "exceeds management fee threshold"
        );
        require(
            defaultPerformance <= PERFORMANCE_FEE_THRESHOLD,
            "exceeds performance fee threshold"
        );
        require(defaultMaxFee <= MAX_BPS, "too high");
        require(defaultMaxGain <= MAX_BPS, "too high");
        require(defaultMaxLoss <= MAX_BPS, "too high");

        feeManager = _feeManager;
        feeRecipient = _feeRecipient;

        defaultConfig = Fee({
            managementFee: defaultManagement,
            performanceFee: defaultPerformance,
            refundRatio: defaultRefund,
            maxFee: defaultMaxFee,
            maxGain: defaultMaxGain,
            maxLoss: defaultMaxLoss
        });

        emit UpdateDefaultFeeConfig(defaultConfig);
    }

    /**
     * @notice Called by a vault when a `strategy` is reporting.
     * @dev The msg.sender must have been added to the `vaults` mapping.
     * @param strategy Address of the strategy reporting.
     * @param gain Amount of the gain if any.
     * @param loss Amount of the loss if any.
     * @return totalFees if any to charge.
     * @return totalRefunds if any for the vault to pull.
     */
    function report(
        address strategy,
        uint256 gain,
        uint256 loss
    ) external returns (uint256 totalFees, uint256 totalRefunds) {
        // Make sure this is a valid vault.
        require(vaults[msg.sender], "!authorized");

        // Declare the config to use
        Fee memory fee;

        // Check if there is a custom config to use.
        if (_custom[msg.sender][strategy] != 0) {
            fee = customConfig[msg.sender][strategy];
        } else {
            // Otherwise use the default.
            fee = defaultConfig;
        }

        // Retrieve the strategy's params from the vault.
        IVault.StrategyParams memory strategyParams = IVault(msg.sender)
            .strategies(strategy);

        // Charge management fees no matter gain or loss.
        if (fee.managementFee > 0) {
            // Time since the last harvest.
            uint256 duration = block.timestamp - strategyParams.last_report;
            // managementFee is an annual amount, so charge based on the time passed.
            totalFees = ((strategyParams.current_debt *
                duration *
                (fee.managementFee)) /
                MAX_BPS /
                SECS_PER_YEAR);
        }

        // Only charge performance fees if there is a gain.
        if (gain > 0) {
            require(
                gain <= (strategyParams.current_debt * (fee.maxGain)) / MAX_BPS,
                "too much gain"
            );
            totalFees += (gain * (fee.performanceFee)) / MAX_BPS;
        } else {
            if (fee.maxLoss < MAX_BPS) {
                require(
                    loss <=
                        (strategyParams.current_debt * (fee.maxLoss)) / MAX_BPS,
                    "too much loss"
                );
            }

            // Means we should have a loss.
            if (fee.refundRatio > 0) {
                // Cache the underlying asset the vault uses.
                address asset = IVault(msg.sender).asset();
                // Give back either all we have or based on the refund ratio.
                totalRefunds = Math.min(
                    (loss * (fee.refundRatio)) / MAX_BPS,
                    ERC20(asset).balanceOf(address(this))
                );

                if (totalRefunds > 0) {
                    // Approve the vault to pull the underlying asset.
                    ERC20(asset).safeApprove(msg.sender, totalRefunds);
                }
            }
        }

        // 0 Max fee means it is not enforced.
        if (fee.maxFee > 0) {
            // Ensure fee does not exceed the maxFee %.
            totalFees = Math.min((gain * (fee.maxFee)) / MAX_BPS, totalFees);
        }

        return (totalFees, totalRefunds);
    }

    /**
     * @notice Function to add a new vault for this accountant to charge fees for.
     * @dev This is not used to set any of the fees for the specific vault or strategy. Each fee will be set separately.
     * @param vault The address of a vault to allow to use this accountant.
     */
    function addVault(address vault) external onlyFeeManager {
        // Ensure the vault has not already been added.
        require(!vaults[vault], "already added");

        vaults[vault] = true;

        emit VaultChanged(vault, ChangeType.ADDED);
    }

    /**
     * @notice Function to remove a vault from this accountant's fee charging list.
     * @param vault The address of the vault to be removed from this accountant.
     */
    function removeVault(address vault) external onlyFeeManager {
        // Ensure the vault has been previously added.
        require(vaults[vault], "not added");

        vaults[vault] = false;

        emit VaultChanged(vault, ChangeType.REMOVED);
    }

    /**
     * @notice Function to update the default fee configuration used for all strategies.
     * @param defaultManagement Default annual management fee to charge.
     * @param defaultPerformance Default performance fee to charge.
     * @param defaultRefund Default refund ratio to give back on losses.
     * @param defaultMaxFee Default max fee to allow as a percent of gain.
     * @param defaultMaxGain Default max percent gain a strategy can report.
     * @param defaultMaxLoss Default max percent loss a strategy can report.
     */
    function updateDefaultConfig(
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) external onlyFeeManager {
        // Check for threshold and limit conditions.
        require(
            defaultManagement <= MANAGEMENT_FEE_THRESHOLD,
            "exceeds management fee threshold"
        );
        require(
            defaultPerformance <= PERFORMANCE_FEE_THRESHOLD,
            "exceeds performance fee threshold"
        );
        require(defaultMaxFee <= MAX_BPS, "too high");
        require(defaultMaxGain <= MAX_BPS, "too high");
        require(defaultMaxLoss <= MAX_BPS, "too high");

        // Update the default fee configuration.
        defaultConfig = Fee({
            managementFee: defaultManagement,
            performanceFee: defaultPerformance,
            refundRatio: defaultRefund,
            maxFee: defaultMaxFee,
            maxGain: defaultMaxGain,
            maxLoss: defaultMaxLoss
        });

        emit UpdateDefaultFeeConfig(defaultConfig);
    }

    /**
     * @notice Function to set a custom fee configuration for a specific strategy in a specific vault.
     * @param vault The vault the strategy is hooked up to.
     * @param strategy The strategy to customize.
     * @param customManagement Custom annual management fee to charge.
     * @param customPerformance Custom performance fee to charge.
     * @param customRefund Custom refund ratio to give back on losses.
     * @param customMaxFee Custom max fee to allow as a percent of gain.
     * @param customMaxGain Custom max percent gain a strategy can report.
     * @param customMaxLoss Custom max percent loss a strategy can report.
     */
    function setCustomConfig(
        address vault,
        address strategy,
        uint16 customManagement,
        uint16 customPerformance,
        uint16 customRefund,
        uint16 customMaxFee,
        uint16 customMaxGain,
        uint16 customMaxLoss
    ) external onlyFeeManager {
        // Ensure the vault has been added.
        require(vaults[vault], "vault not added");
        // Check for threshold and limit conditions.
        require(
            customManagement <= MANAGEMENT_FEE_THRESHOLD,
            "exceeds management fee threshold"
        );
        require(
            customPerformance <= PERFORMANCE_FEE_THRESHOLD,
            "exceeds performance fee threshold"
        );
        require(customMaxFee <= MAX_BPS, "too high");
        require(customMaxGain <= MAX_BPS, "too high");
        require(customMaxLoss <= MAX_BPS, "too high");

        // Set the strategy's custom config.
        customConfig[vault][strategy] = Fee({
            managementFee: customManagement,
            performanceFee: customPerformance,
            refundRatio: customRefund,
            maxFee: customMaxFee,
            maxGain: customMaxGain,
            maxLoss: customMaxLoss
        });

        // Set the custom flag.
        _custom[vault][strategy] = 1;

        emit UpdateCustomFeeConfig(
            vault,
            strategy,
            customConfig[vault][strategy]
        );
    }

    /**
     * @notice Function to remove a previously set custom fee configuration for a strategy.
     * @param vault The vault to remove custom setting for.
     * @param strategy The strategy to remove custom setting for.
     */
    function removeCustomConfig(
        address vault,
        address strategy
    ) external onlyFeeManager {
        // Ensure custom fees are set for the specified vault and strategy.
        require(_custom[vault][strategy] != 0, "No custom fees set");

        // Set all the strategy's custom fees to 0.
        delete customConfig[vault][strategy];

        // Clear the custom flag.
        _custom[vault][strategy] = 0;

        // Emit relevant event.
        emit RemovedCustomFeeConfig(vault, strategy);
    }

    /**
     * @notice Public getter to check for custom setting.
     * @dev We use uint256 for the flag since its cheaper so this
     *   will convert it to a bool for easy view functions.
     *
     * @param vault Address of the vault.
     * @param strategy Address of the strategy
     * @return If a custom fee config is set.
     */
    function custom(
        address vault,
        address strategy
    ) external view returns (bool) {
        return _custom[vault][strategy] != 0;
    }

    /**
     * @notice Function to withdraw the underlying asset from a vault.
     * @param vault The vault to withdraw from.
     * @param amount The amount in the underlying to withdraw.
     */
    function withdrawUnderlying(
        address vault,
        uint256 amount
    ) external onlyFeeManager {
        IVault(vault).withdraw(amount, address(this), address(this), maxLoss);
    }

    /**
     * @notice Sets the `maxLoss` parameter to be used on withdraws.
     * @param _maxLoss The amount in basis points to set as the maximum loss.
     */
    function setMaxLoss(uint256 _maxLoss) external onlyFeeManager {
        // Ensure that the provided `maxLoss` does not exceed 100% (in basis points).
        require(_maxLoss <= MAX_BPS, "higher than 100%");

        maxLoss = _maxLoss;

        // Emit an event to signal the update of the `maxLoss` parameter.
        emit UpdateMaxLoss(_maxLoss);
    }

    /**
     * @notice Function to distribute all accumulated fees to the designated recipient.
     * @param token The token to distribute.
     */
    function distribute(address token) external {
        distribute(token, ERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Function to distribute accumulated fees to the designated recipient.
     * @param token The token to distribute.
     * @param amount amount of token to distribute.
     */
    function distribute(address token, uint256 amount) public onlyFeeManager {
        ERC20(token).safeTransfer(feeRecipient, amount);

        emit DistributeRewards(token, amount);
    }

    /**
     * @notice Function to set a future fee manager address.
     * @param _futureFeeManager The address to set as the future fee manager.
     */
    function setFutureFeeManager(
        address _futureFeeManager
    ) external onlyFeeManager {
        // Ensure the futureFeeManager is not a zero address.
        require(_futureFeeManager != address(0), "ZERO ADDRESS");
        futureFeeManager = _futureFeeManager;

        emit SetFutureFeeManager(_futureFeeManager);
    }

    /**
     * @notice Function to accept the role change and become the new fee manager.
     * @dev This function allows the future fee manager to accept the role change and become the new fee manager.
     */
    function acceptFeeManager() external {
        // Make sure the sender is the future fee manager.
        require(msg.sender == futureFeeManager, "not future fee manager");
        feeManager = futureFeeManager;
        futureFeeManager = address(0);

        emit NewFeeManager(msg.sender);
    }

    /**
     * @notice Function to set a new address to receive distributed rewards.
     * @param newFeeRecipient Address to receive distributed fees.
     */
    function setFeeRecipient(address newFeeRecipient) external onlyFeeManager {
        // Ensure the newFeeRecipient is not a zero address.
        require(newFeeRecipient != address(0), "ZERO ADDRESS");
        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;

        emit UpdateFeeRecipient(oldRecipient, newFeeRecipient);
    }

    /**
     * @notice View function to get the max a performance fee can be.
     * @dev This function provides the maximum performance fee that the accountant can charge.
     * @return The maximum performance fee.
     */
    function performanceFeeThreshold() external view returns (uint16) {
        return PERFORMANCE_FEE_THRESHOLD;
    }

    /**
     * @notice View function to get the max a management fee can be.
     * @dev This function provides the maximum management fee that the accountant can charge.
     * @return The maximum management fee.
     */
    function managementFeeThreshold() external view returns (uint16) {
        return MANAGEMENT_FEE_THRESHOLD;
    }
}
