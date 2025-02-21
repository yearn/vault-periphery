// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";
import {IV2Vault} from "../interfaces/IV2Vault.sol";

contract V2VaultGovernance is Governance2Step {
    event TimelockSet(uint256 timelock);
    event StrategyAdded(
        address indexed vault,
        address indexed strategy,
        uint256 timestamp
    );
    event AddingStrategiesDisabled(address indexed vault);

    // Timelock duration for adding new strategies
    uint256 public constant timelock = 7 days;

    // Mapping of vault to strategy to timestamp when it can be added
    mapping(address => mapping(address => uint256)) public strategyTimelocks;

    // Whether adding new strategies is permanently disabled for vault
    mapping(address => bool) public addingStrategiesDisabled;

    constructor(address _governance) Governance2Step(_governance) {}

    // Special functions for strategy addition control

    /// @notice Initiates a timelock for adding a strategy to a vault
    function initiateStrategyTimelock(
        address _vault,
        address _strategy
    ) external onlyGovernance {
        require(!addingStrategiesDisabled[_vault], "ADDING DISABLED");
        require(strategyTimelocks[_vault][_strategy] == 0, "ALREADY INITIATED");
        strategyTimelocks[_vault][_strategy] = block.timestamp + timelock;
        emit StrategyAdded(
            _vault,
            _strategy,
            strategyTimelocks[_vault][_strategy]
        );
    }

    /// @notice Irreversibly disables adding strategies to a vault
    function disableAddingStrategies(address _vault) external onlyGovernance {
        addingStrategiesDisabled[_vault] = true;
        emit AddingStrategiesDisabled(_vault);
    }

    // Pass-through governance functions

    function setName(
        address _vault,
        string memory _name
    ) external onlyGovernance {
        IV2Vault(_vault).setName(_name);
    }

    function setSymbol(
        address _vault,
        string memory _symbol
    ) external onlyGovernance {
        IV2Vault(_vault).setSymbol(_symbol);
    }

    // Timelock or never allow?
    /**
    function setGovernance(address _vault, address _governance) external onlyGovernance {
        IV2Vault(_vault).setGovernance(_governance);
    }
    */

    function acceptGovernance(address _vault) external onlyGovernance {
        IV2Vault(_vault).acceptGovernance();
    }

    /**
    function setManagement(address _vault, address _management) external onlyGovernance {
        IV2Vault(_vault).setManagement(_management);
    }
    */

    function setGuardian(
        address _vault,
        address _guardian
    ) external onlyGovernance {
        IV2Vault(_vault).setGuardian(_guardian);
    }

    /**
    function setRewards(address _vault, address _rewards) external onlyGovernance {
        IV2Vault(_vault).setRewards(_rewards);
    }
    */

    function setLockedProfitDegradation(
        address _vault,
        uint256 _degradation
    ) external onlyGovernance {
        IV2Vault(_vault).setLockedProfitDegradation(_degradation);
    }

    function setDepositLimit(
        address _vault,
        uint256 _limit
    ) external onlyGovernance {
        IV2Vault(_vault).setDepositLimit(_limit);
    }

    function setPerformanceFee(
        address _vault,
        uint256 _fee
    ) external onlyGovernance {
        IV2Vault(_vault).setPerformanceFee(_fee);
    }

    function setManagementFee(
        address _vault,
        uint256 _fee
    ) external onlyGovernance {
        IV2Vault(_vault).setManagementFee(_fee);
    }

    function setEmergencyShutdown(
        address _vault,
        bool _active
    ) external onlyGovernance {
        IV2Vault(_vault).setEmergencyShutdown(_active);
    }

    function setWithdrawalQueue(
        address _vault,
        address[] memory _queue
    ) external onlyGovernance {
        IV2Vault(_vault).setWithdrawalQueue(_queue);
    }

    function addStrategy(address _vault, address _strategy) external {
        require(!addingStrategiesDisabled[_vault], "ADDING DISABLED");
        uint256 allowedAt = strategyTimelocks[_vault][_strategy];
        require(
            allowedAt != 0 && block.timestamp >= allowedAt,
            "NOT TIMELOCKED"
        );

        IV2Vault(_vault).addStrategy(_strategy, 0, 0, 2 ** 256 - 1, 0);

        // Clear the timelock after successful addition
        strategyTimelocks[_vault][_strategy] = 0;
    }

    /// TODO Disable changing debt ratio? Needs SMS to fund strategy
    function updateStrategyDebtRatio(
        address _vault,
        address _strategy,
        uint256 _debtRatio
    ) external onlyGovernance {
        IV2Vault(_vault).updateStrategyDebtRatio(_strategy, _debtRatio);
    }

    function updateStrategyMinDebtPerHarvest(
        address _vault,
        address _strategy,
        uint256 _minDebtPerHarvest
    ) external onlyGovernance {
        IV2Vault(_vault).updateStrategyMinDebtPerHarvest(
            _strategy,
            _minDebtPerHarvest
        );
    }

    function updateStrategyMaxDebtPerHarvest(
        address _vault,
        address _strategy,
        uint256 _maxDebtPerHarvest
    ) external onlyGovernance {
        IV2Vault(_vault).updateStrategyMaxDebtPerHarvest(
            _strategy,
            _maxDebtPerHarvest
        );
    }

    function updateStrategyPerformanceFee(
        address _vault,
        address _strategy,
        uint256 _performanceFee
    ) external onlyGovernance {
        IV2Vault(_vault).updateStrategyPerformanceFee(
            _strategy,
            _performanceFee
        );
    }

    // TODO Timelock?
    /**
    function migrateStrategy(
        address _vault,
        address _oldStrategy,
        address _newStrategy
    ) external onlyGovernance {
        IV2Vault(_vault).migrateStrategy(_oldStrategy, _newStrategy);
    }
    */

    function revokeStrategy(
        address _vault,
        address _strategy
    ) external onlyGovernance {
        IV2Vault(_vault).revokeStrategy(_strategy);
    }

    // NOTE: Causes losses
    function revokeStrategy(
        address _vault,
        address _strategy,
        bool _force
    ) external onlyGovernance {
        IV2Vault(_vault).revokeStrategy(_strategy, _force);
    }

    function addStrategyToQueue(
        address _vault,
        address _strategy
    ) external onlyGovernance {
        IV2Vault(_vault).addStrategyToQueue(_strategy);
    }

    function removeStrategyFromQueue(
        address _vault,
        address _strategy
    ) external onlyGovernance {
        IV2Vault(_vault).removeStrategyFromQueue(_strategy);
    }
}
