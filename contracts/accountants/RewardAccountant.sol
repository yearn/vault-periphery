// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {HealthCheckAccountant, ERC20, SafeERC20, IVault} from "./HealthCheckAccountant.sol";

contract RewardAccountant is HealthCheckAccountant {
    using SafeERC20 for ERC20;

    event UpdateRewardRefund(
        address indexed vault,
        address indexed strategy,
        bool refund,
        uint256 amount
    );

    struct RewardRefund {
        bool refund;
        uint248 amount;
    }

    // Mapping of vault => strategy => struct if there is a reward refund to give.
    mapping(address => mapping(address => RewardRefund)) public rewardRefund;

    constructor(
        address _feeManager,
        address _feeRecipient,
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    )
        HealthCheckAccountant(
            _feeManager,
            _feeRecipient,
            defaultManagement,
            defaultPerformance,
            defaultRefund,
            defaultMaxFee,
            defaultMaxGain,
            defaultMaxLoss
        )
    {}

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
    ) public override returns (uint256 totalFees, uint256 totalRefunds) {
        // If the strategy is a reward refunder.
        if (rewardRefund[msg.sender][strategy].refund) {
            uint256 amount = uint256(rewardRefund[msg.sender][strategy].amount);

            // Make sure the vault is max approved.
            ERC20(IVault(msg.sender).asset()).safeApprove(msg.sender, amount);

            // The vault will pull the full balance of if less than amount.
            return (0, amount);
        } else {
            return super.report(strategy, gain, loss);
        }
    }

    /**
     * @notice Set a strategy to use to refund a reward amount for
     * aut compounding reward tokens.
     *
     * @param _vault Address of the vault to refund.
     * @param _strategy Address of the strategy to refund during the report.
     * @param _refund Bool to turn it on or off.
     * @param _amount Amount to refund per report.
     */
    function setRewardRefund(
        address _vault,
        address _strategy,
        bool _refund,
        uint256 _amount
    ) external onlyFeeManager {
        require(vaults[_vault], "not added");
        require(
            IVault(_vault).strategies(_strategy).activation != 0,
            "!active"
        );
        require(_refund || _amount == 0, "no refund and non zero amount");

        rewardRefund[_vault][_strategy] = RewardRefund({
            refund: _refund,
            amount: uint248(_amount)
        });

        emit UpdateRewardRefund(_vault, _strategy, _refund, uint256(_amount));
    }
}
