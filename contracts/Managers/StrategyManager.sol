// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstants} from "@yearn-vaults/interfaces/VaultConstants.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

contract StrategyManager is Governance, VaultConstants {
    struct StrategyInfo {
        address strategy;
        uint256 maxDebt;
        uint256 targetRatio;
        uint256 maxRatio;
    }

    mapping (address => StrategyInfo) public strategyInfo;

    address[] public strategies;

    constructor(address _governance) Governance(_governance) {}

    function addStrategy(address _vault, address _strategy, uint256 _maxDebt) external onlyGovernance {
        
    }

    function updateStrategyMaxDebt(address _vault, address _strategy, uint256 _maxDebt) external onlyGovernance {
        IVault(_vault).update_max_debt_for_strategy(_strategy, _maxDebt);
    }

    function removeStrategy(address _vault, address _strategy) external onlyGovernance {
        IVault(_vault).revoke_strategy(_strategy);
    }

    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }
}
