// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Accountant} from "./Accountant.sol";

/**
 * @title AccountantFactory
 * @dev A factory contract for deploying Accountant contracts
 */
contract AccountantFactory {
    event NewAccountant(address indexed newAccountant);

    Accountant.Fee public defaultConfig;

    /**
     * @dev Constructor initializes the default configuration
     */
    constructor() {
        defaultConfig = Accountant.Fee({
            managementFee: 0,
            performanceFee: 1_000,
            refundRatio: 0,
            maxFee: 10_000,
            maxGain: 20_000,
            maxLoss: 1,
            custom: false
        });
    }

    /**
     * @dev Deploys a new Accountant contract with default configuration
     * @return _newAccountant The address of the newly deployed Accountant contract
     */
    function newAccountant() external returns (address) {
        return
            newAccountant(
                msg.sender,
                msg.sender,
                defaultConfig.managementFee,
                defaultConfig.performanceFee,
                defaultConfig.refundRatio,
                defaultConfig.maxFee,
                defaultConfig.maxGain,
                defaultConfig.maxLoss
            );
    }

    /**
     * @dev Deploys a new Accountant contract with specified fee manager and recipient
     * @param feeManager The address to receive management and performance fees
     * @param feeRecipient The address to receive refund fees
     * @return _newAccountant The address of the newly deployed Accountant contract
     */
    function newAccountant(
        address feeManager,
        address feeRecipient
    ) external returns (address) {
        return
            newAccountant(
                feeManager,
                feeRecipient,
                defaultConfig.managementFee,
                defaultConfig.performanceFee,
                defaultConfig.refundRatio,
                defaultConfig.maxFee,
                defaultConfig.maxGain,
                defaultConfig.maxLoss
            );
    }

    /**
     * @dev Deploys a new Accountant contract with specified fee configurations
     * @param defaultManagement Default management fee
     * @param defaultPerformance Default performance fee
     * @param defaultRefund Default refund ratio
     * @param defaultMaxFee Default maximum fee
     * @param defaultMaxGain Default maximum gain
     * @param defaultMaxLoss Default maximum loss
     * @return _newAccountant The address of the newly deployed Accountant contract
     */
    function newAccountant(
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) external returns (address) {
        return
            newAccountant(
                msg.sender,
                msg.sender,
                defaultManagement,
                defaultPerformance,
                defaultRefund,
                defaultMaxFee,
                defaultMaxGain,
                defaultMaxLoss
            );
    }

    /**
     * @dev Deploys a new Accountant contract with specified fee configurations and addresses
     * @param feeManager The address to receive management and performance fees
     * @param feeRecipient The address to receive refund fees
     * @param defaultManagement Default management fee
     * @param defaultPerformance Default performance fee
     * @param defaultRefund Default refund ratio
     * @param defaultMaxFee Default maximum fee
     * @param defaultMaxGain Default maximum gain
     * @param defaultMaxLoss Default maximum loss
     * @return _newAccountant The address of the newly deployed Accountant contract
     */
    function newAccountant(
        address feeManager,
        address feeRecipient,
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) public returns (address _newAccountant) {
        _newAccountant = address(
            new Accountant(
                feeManager,
                feeRecipient,
                defaultManagement,
                defaultPerformance,
                defaultRefund,
                defaultMaxFee,
                defaultMaxGain,
                defaultMaxLoss
            )
        );

        emit NewAccountant(_newAccountant);
    }
}
