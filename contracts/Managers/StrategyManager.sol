// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {RoleManager, IVault} from "./RoleManager.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

contract RiskScore {
    function getRating(address _strategy) external view returns (uint256) {}
}

contract StrategyManager is Governance2Step {
    address public roleManager;
    address public riskScore;

    constructor(address _governance) Governance2Step(_governance) {}

    function addStrategyToVault(
        address _strategy,
        address _vault
    ) external virtual {
        // Get the rating for the vault and strategy.
        uint256 vaultRating = RoleManager(roleManager).getRating(_vault);
        uint256 strategyRating = RiskScore(riskScore).getRating(_strategy);
        require(strategyRating != 0, "strategy not rated");
        require(vaultRating >= strategyRating, "strategy rated too low");
        IVault(_vault).add_strategy(_strategy);
    }

    function removeStrategyFromVault(
        address _strategy,
        address _vault
    ) external virtual onlyGovernance {
        require(
            RoleManager(roleManager).isVaultsRoleManager(_vault),
            "not role manager"
        );
        IVault(_vault).revoke_strategy(_strategy);
    }

    function setRoleManager(
        address _newRoleManager
    ) external virtual onlyGovernance {
        roleManager = _newRoleManager;
    }

    function setRiskScore(
        address _newRiskScore
    ) external virtual onlyGovernance {
        riskScore = _newRiskScore;
    }
}
