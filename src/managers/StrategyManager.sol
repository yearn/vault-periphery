// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";
import {RoleManager} from "./RoleManager.sol";

interface IStrategyFactory {
    function isDeployedStrategy(address _strategy) external view returns (bool);
}

contract StrategyManager is Governance2Step {
    struct TimestampWithValue {
        uint128 timestampSet;
        uint128 value;
    }

    address public immutable roleManager;

    uint256 public timeLock;

    TimestampWithValue public pendingTimeLock;

    mapping(address => TimestampWithValue) public strategies;

    mapping(address => TimestampWithValue) public strategyFactories;

    constructor(
        address _governance,
        address _roleManager
    ) Governance2Step(_governance) {
        roleManager = _roleManager;
        timeLock = 1 days;
    }

    function addStrategyFactory(
        address _factory,
        uint256 _category
    ) external virtual onlyGovernance {
        strategyFactories[_factory] = TimestampWithValue({
            timestampSet: uint128(block.timestamp),
            value: uint128(_category)
        });
    }

    function removeStrategyFactory(
        address _factory
    ) external virtual onlyGovernance {
        delete strategyFactories[_factory];
    }

    function addStrategy(
        address _strategy,
        uint256 _category
    ) external virtual onlyGovernance {
        strategies[_strategy] = TimestampWithValue({
            timestampSet: uint128(block.timestamp),
            value: uint128(_category)
        });
    }

    function removeStrategy(address _strategy) external virtual onlyGovernance {
        delete strategies[_strategy];
    }

    function addStrategyToVault(
        address _strategy,
        address _vault
    ) external virtual {
        TimestampWithValue memory strategyStatus = strategies[_strategy];

        _hasPassedTimeLock(strategyStatus.timestampSet);

        _isValidCategory(strategyStatus.value, _vault);

        IVault(_vault).add_strategy(_strategy);
    }

    function addStrategyToVaultFromFactory(
        address _strategy,
        address _factory,
        address _vault
    ) external virtual {
        TimestampWithValue memory factoryStatus = strategyFactories[_factory];

        _hasPassedTimeLock(factoryStatus.timestampSet);

        _isValidCategory(factoryStatus.value, _vault);

        require(
            IStrategyFactory(_factory).isDeployedStrategy(_strategy),
            "StrategyManager: invalid strategy"
        );

        IVault(_vault).add_strategy(_strategy);
    }

    function setNewTimeLock(
        uint256 _newTimeLock
    ) external virtual onlyGovernance {
        pendingTimeLock = TimestampWithValue({
            timestampSet: uint128(block.timestamp),
            value: uint128(_newTimeLock)
        });
    }

    function acceptNewTimeLock() external virtual {
        _hasPassedTimeLock(pendingTimeLock.timestampSet);

        timeLock = pendingTimeLock.value;
        delete pendingTimeLock;
    }

    function hasPassedTimeLock(address _strategy) external view virtual returns (bool) {
        _hasPassedTimeLock(strategies[_strategy].timestampSet);
        return true;
    }

    function _hasPassedTimeLock(uint256 _timeAdded) internal view virtual {
        require(
            _timeAdded != 0 && _timeAdded + timeLock < block.timestamp,
            "StrategyManager: has not passed time lock"
        );
    }

    function isValidCategory(address _strategy, address _vault) external view virtual returns (bool) {
        _isValidCategory(strategies[_strategy].value, _vault);
        return true;
    }

    function _isValidCategory(
        uint256 _category,
        address _vault
    ) internal view virtual {
        uint256 vaultCategory = RoleManager(roleManager).getCategory(_vault);
        require(
            _category <= vaultCategory,
            "StrategyManager: invalid category"
        );
    }
}
