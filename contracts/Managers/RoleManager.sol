// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstant} from "@yearn-vaults/interfaces/VaultConstants.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {Registry} from "../registry/Registry.sol";
import {GenericDebAllocatorFactory, GenericDebAllocator} from "../debtAllocators/GenericDebAllocatorFactory.sol";

contract RoleManager is Governance, VaultConstants {
    struct VaultConfig {
        address asset;
        address debtAllocator;
        uint256 rating;
        StrategyInfo[] strategies;
    }

    struct StrategyInfo {
        address strategy;
        uint256 maxDebt;
        uint256 targetRatio
        uint256 minChange;
    }

    address public daddy;
    address public brain;
    address public security;
    address public keeper;
    address public accountant;
    address public registry;
    address public allocatorFactory;

    uint256 public daddyRoles;
    uint256 public brainRoles;
    uint256 public securityRoles;
    uint256 public keeperRoles;

    uint256 public defaultProfitMaxUnlock = 10 days;

    mapping(address => VaultConfig) public vaultConfig;

    address[] public vaults;

    constructor(address _gov) Governance(_gov) {
        daddyRoles = ALL;
        brainRoles = REPORTING_MANAGER | DEBT_MANAGER | QUEUE_MANAGER;
        keeperRoles = REPORTING_MANAGER | DEBT_MANAGER;
        securityRoles = MAX_DEBT_MANAGER;
    }

    /// NEW VAULT
    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        return newVault(_asset, _name, _symbol, defaultProfitMaxUnlock);
    }

    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _profitMaxUnlockTime,
        uint256 _rating,
        uint256 _depositLimit
        StrategyInfo[] memory _strategies
    ) external onlyGovernance returns (address _vault) {
        _vault = Registry(registry).newEndorsedVault(_asset, _name, _symbol, address(this), _profitMaxUnlockTime);

        _sanctify(_vault);

        _setStrategies(_vault, strategies);

        address _debtAllocator = _allocate(_vault, _strategies);

        _limit(_vault, _depositLimit);

        vaultConfig[_vault] = VaultConfig({
            asset: _asset;
            debtAllocator: _debtAllocator;
            rating: _rating;
            strategies: _strategies
        });

        vault.push(_vault);
    }

    // GIVE OUT ROLES
    function _sanctify(address _vault) internal {
        IVault(_vault).set_role(
            address(this),
            ALL
        );

        IVault(_vault).set_role(
            daddy,
            daddyRoles
        );

        IVault(_vault).set_role(
            brain, 
            brainRoles
        );

        IVault(_vault).set_role(keeper, keeperRoles);

        IVault(_vault).set_role(security, securityRoles);

        IVault(_vault).set_accountant(accountant);
    }

    /// ADD STRATEGIES
    function _setStrategies(address _vault, StrategyInfo[] memory _strategies) internal {
        for(uint256 i = 0; i < _strategies.length, ++i) {
            _setStrategy(_vault, _strategies[i]);
        }
    }

    function _setStrategy(address _vault, StrategyInfo memory _strategy) internal {
        // This will check both that the strategy has been endorsed and
        // uses the same underlying asset with one call.
        require(Registry(registry).vaultInfo(_strategy.strategy).asset == IVault(_vault).asset(), "!endorsed");

        IVault(_vault).add_strategy(_strategy.strategy);

        IVault(_vault).update_max_debt_for_strategy(
            _strategy.strategy,
            _strategy.maxDebt
        );
    }

    // DEbt allocator
    function _allocate(address _vault, StrategyInfo memory _strategies) internal returns (address _debtAllocator) {
        _debtAllocator = GenericDebtAllocatorFactory(allocatorFactory).newGenericDebtAllocator(_vault);

        for(uint256 i = 0; i < _strategies.length, ++i) {
            _allocateStrategy(_debtAllocator, _strategies[i]);
        }


    }

    function _allocateStrategy(address _debtAllocator, StrategyInfo _strategy) internal {
        
    }

    function _limit(address _vault, uint256 _depositLimit) internal {
        IVault(_vault).set_deposit_limit(_depositLimit)
    }
    

    // ADJUST DEBT

    // REPORT
}
