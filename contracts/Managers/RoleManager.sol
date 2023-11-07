// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstants} from "@yearn-vaults/interfaces/VaultConstants.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {Registry} from "../registry/Registry.sol";
import {GenericDebtAllocatorFactory, GenericDebtAllocator} from "../debtAllocators/GenericDebtAllocatorFactory.sol";

contract RoleManager is Governance, VaultConstants {
    struct VaultConfig {
        address asset;
        address debtAllocator;
        uint256 rating;
        uint256 minDebtChange;
        StrategyInfo[] strategies;
    }

    struct StrategyInfo {
        address strategy;
        uint256 maxDebt;
        uint256 targetRatio;
        uint256 maxRatio;
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

    uint256 public maxAcceptableBaseFee = 100e9;

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
        string memory _symbol,
        uint256 _rating
    ) external returns (address) {
        return
            newVault(
                _asset,
                _name,
                _symbol,
                _rating,
                defaultProfitMaxUnlock,
                0
            );
    }

    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _rating,
        uint256 _profitMaxUnlockTime,
        uint256 _depositLimit
    ) public onlyGovernance returns (address _vault) {
        _vault = Registry(registry).newEndorsedVault(
            _asset,
            _name,
            _symbol,
            address(this),
            _profitMaxUnlockTime
        );

        _sanctify(_vault);

        address _debtAllocator = _deployAllocator(_vault);

        vaultConfig[_vault] = VaultConfig({
            asset: _asset,
            debtAllocator: _debtAllocator,
            rating: _rating,
            minDebtChange: _depositLimit / 10,
            strategies: new StrategyInfo[](0)
        });

        vaults.push(_vault);
    }

    // GIVE OUT ROLES
    function _sanctify(address _vault) internal {
        IVault(_vault).set_role(daddy, daddyRoles);

        IVault(_vault).set_role(brain, brainRoles);

        IVault(_vault).set_role(keeper, keeperRoles);

        IVault(_vault).set_role(security, securityRoles);

        IVault(_vault).set_accountant(accountant);

        HealthCheckAccountant(accountant).addVault(_vault);
    }

     // DEbt allocator
    function _deployAllocator(
        address _vault
    ) internal returns (address _debtAllocator) {
        _debtAllocator = GenericDebtAllocatorFactory(allocatorFactory)
            .newGenericDebtAllocator(_vault);
        
        GenericDebtAllocator(_debtAllocator).setMaxAcceptableBaseFee(maxAcceptableBaseFee);

        // Give sms control of the debt allocator.
        GenericDebtAllocator(_debtAllocator).transferGovernance(brain);        
    }

    function _allocateStrategy(
        address _debtAllocator,
        StrategyInfo memory _strategy
    ) internal {
        GenericDebtAllocator(_debtAllocator).setTargetDebtRatio(
            _strategy.strategy,
            _strategy.targetRatio
        );
    }

    function _limit(address _vault, uint256 _depositLimit) internal {
        IVault(_vault).set_deposit_limit(_depositLimit);
    }

    function setRole(address _vault, address _account, uint256 _role) external onlyGovernance {
        IVault(_vault).set_role(_account, _role);
    }

    function transferRoleManager(address _vault, address _newManager) external onlyGovernance {
        IVault(_vault).transfer_role_manager(_newManager);
    }

    function acceptRoleManager(address _vault) external onlyGovernance {
        IVault(_vault).accept_role_manager();

        vaultConfig[_vault].asset = IVault(_vault).asset();

        vaults.push(_vault);
    }

    function setAccountant(address _newAccountant) external onlyGovernance {
        // Transfer ownership over the last accountant to daddy.        
        if (accountant != address(0)) {
            HealthCheckAccountant(accountant).setFutureFeeManager(daddy);
        }

        HealthCheckAccountant(_newAccountant).acceptFeeManager();

        accountant = _newAccountant;
    }
}
