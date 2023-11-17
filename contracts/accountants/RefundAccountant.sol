// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {HealthCheckAccountant, ERC20, SafeERC20, IVault} from "./HealthCheckAccountant.sol";

/// @title Refund Accountant
/// @dev Allows for configurable refunds to be given to specific strategies for a vault.
///     This can be used to auto compound reward into vault or provide retroactive refunds
///     from a previous loss.
contract RefundAccountant is HealthCheckAccountant {
    using SafeERC20 for ERC20;

    /// @notice An event emitted when a refund is added for a strategy.
    event UpdateRefund(
        address indexed vault,
        address indexed strategy,
        bool refund,
        uint256 amount
    );

    /// @notice Struct to hold refund info for a strategy.
    struct Refund {
        // If the accountant should refund on the report.
        bool refund;
        // The amount if any to refund.
        uint248 amount;
    }

    /// @notice Mapping of vault => strategy => struct if there is a reward refund to give.
    mapping(address => mapping(address => Refund)) public refund;

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
    )
        public
        virtual
        override
        returns (uint256 totalFees, uint256 totalRefunds)
    {
        (totalFees, totalRefunds) = super.report(strategy, gain, loss);

        Refund memory refundConfig = refund[msg.sender][strategy];
        // Check if the strategy is being given a refund.
        if (refundConfig.refund) {
            // Add it to the existing refunds.
            totalRefunds += uint256(refundConfig.amount);

            // Make sure the vault is approved correctly.
            _checkAllowance(
                msg.sender,
                IVault(msg.sender).asset(),
                totalRefunds
            );

            // Always reset the refund amount so it can't be reused.
            delete refund[msg.sender][strategy];
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
    function setRefund(
        address _vault,
        address _strategy,
        bool _refund,
        uint256 _amount
    ) external virtual onlyFeeManager {
        require(vaults[_vault], "not added");
        require(
            IVault(_vault).strategies(_strategy).activation != 0,
            "!active"
        );
        require(_refund || _amount == 0, "no refund and non zero amount");

        refund[_vault][_strategy] = Refund({
            refund: _refund,
            amount: uint248(_amount)
        });

        emit UpdateRefund(_vault, _strategy, _refund, uint256(_amount));
    }
}
