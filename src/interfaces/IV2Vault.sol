// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IV2Vault {
    function governance() external view returns (address);

    function pendingGovernance() external view returns (address);

    function managementFee() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function debtRatio() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function lastReport() external view returns (uint256);

    function activation() external view returns (uint256);

    function lockedProfit() external view returns (uint256);

    function lockedProfitDegradation() external view returns (uint256);

    function rewards() external view returns (address);

    function guardian() external view returns (address);

    function management() external view returns (address);

    function emergencyShutdown() external view returns (bool);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function setName(string memory) external;

    function setSymbol(string memory) external;

    function setGovernance(address) external;

    function acceptGovernance() external;

    function setManagement(address) external;

    function setRewards(address) external;

    function setLockedProfitDegradation(uint256) external;

    function setDepositLimit(uint256) external;

    function setPerformanceFee(uint256) external;

    function setManagementFee(uint256) external;

    function setGuardian(address) external;

    function setEmergencyShutdown(bool) external;

    function addStrategy(address, uint256, uint256, uint256, uint256) external;

    function updateStrategyDebtRatio(address, uint256) external;

    function updateStrategyMinDebtPerHarvest(address, uint256) external;

    function updateStrategyMaxDebtPerHarvest(address, uint256) external;

    function updateStrategyPerformanceFee(address, uint256) external;

    function migrateStrategy(address, address) external;

    function revokeStrategy(address) external;

    function revokeStrategy(address, bool) external;

    function setWithdrawalQueue(address[] memory) external;

    function addStrategyToQueue(address) external;

    function removeStrategyFromQueue(address) external;
}
