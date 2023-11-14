// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstants} from "@yearn-vaults/interfaces/VaultConstants.sol";

import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {Registry} from "../registry/Registry.sol";
import {GenericDebtAllocatorFactory, GenericDebtAllocator} from "../debtAllocators/GenericDebtAllocatorFactory.sol";

import {StrategyManager} from "./StrategyManager.sol";

// TODO:
// Endorsers in the registry
// Strategy Manager
// 2 step governance

contract RoleManager is Governance, VaultConstants {
    /// @notice Emitted when a new address is set for a position.
    event UpdateAddress(bytes32 position, address indexed newAddress);

    /// @notice Emitted when a new set of roles is set for a position
    event UpdateRole(bytes32 position, uint256 newRoles);

    /// @notice Emitted when the defaultProfitMaxUnlock variable is updated.
    event UpdateDefaultProfitMaxUnlock(uint256 newDefaultProfitMaxUnlock);

    /// @notice Emitted when the maxAcceptableBaseFee variable is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    struct VaultConfig {
        address asset;
        uint256 rating;
        address debtAllocator;
        uint256 index;
    }

    struct Roles {
        address _address;
        uint96 _roles;
    }

    /// @notice Hash of the role name "daddy".
    bytes32 public constant DADDY = keccak256("daddy");
    /// @notice Hash of the role name "brain".
    bytes32 public constant BRAIN = keccak256("brain");
    /// @notice Hash of the role name "security".
    bytes32 public constant SECURITY = keccak256("security");
    /// @notice Hash of the role name "keeper".
    bytes32 public constant KEEPER = keccak256("keeper");

    /// @notice Immutable address storing the RoleManager contract for role transfers.
    address public immutable role_manager_transfer;

    /// @notice Mapping of role hashes to role information.
    mapping(bytes32 => Roles) public roles;
    /// @notice Mapping of vault addresses to their configurations.
    mapping(address => VaultConfig) public vaultConfig;

    /// @notice Array storing addresses of all managed vaults.
    address[] public vaults;
    /// @notice Address of the accountant.
    address public accountant;
    /// @notice Address of the registry contract.
    address public registry;
    /// @notice Address of the allocator factory contract.
    address public allocatorFactory;
    
    /// @notice Default time until profits are fully unlocked for new vaults.
    uint256 public defaultProfitMaxUnlock = 10 days;
    /// @notice Maximum acceptable base fee for debt allocators.
    uint256 public maxAcceptableBaseFee = 100e9;

    constructor(
        address _gov,
        address _daddy,
        address _brain,
        address _keeper,
        address _security
    ) Governance(_gov) {
        // Set the immutable address that will take over role manager
        // if a vault is removed.
        role_manager_transfer = _daddy;

        roles[DADDY] = Roles({_address: _daddy, _roles: uint96(ALL)});

        roles[BRAIN] = Roles({
            _address: _brain,
            _roles: uint96(REPORTING_MANAGER | DEBT_MANAGER | QUEUE_MANAGER)
        });

        roles[KEEPER] = Roles({
            _address: _keeper,
            _roles: uint96(REPORTING_MANAGER | DEBT_MANAGER)
        });

        roles[SECURITY] = Roles({
            _address: _security,
            _roles: uint96(MAX_DEBT_MANAGER)
        });
    }

    /**
     * @notice Creates a new endorsed vault with default profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _name Name of the vault.
     * @param _symbol Symbol of the vault.
     * @param _rating Rating of the vault.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _rating
    ) external virtual returns (address) {
        return
            newVault(_asset, _name, _symbol, _rating, defaultProfitMaxUnlock);
    }

    /**
     * @notice Creates a new endorsed vault with specified profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _name Name of the vault.
     * @param _symbol Symbol of the vault.
     * @param _rating Rating of the vault.
     * @param _profitMaxUnlockTime Time until profits are fully unlocked.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _rating,
        uint256 _profitMaxUnlockTime
    ) public virtual onlyGovernance returns (address _vault) {
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
            rating: _rating,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        vaults.push(_vault);
    }

    /**
     * @dev Assigns roles to the newly created vault and performs additional configurations.
     * @param _vault Address of the vault to sanctify.
     */
    function _sanctify(address _vault) internal virtual {
        Roles memory roleInfo = roles[DADDY];
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[BRAIN];
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[KEEPER];
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[SECURITY];
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        IVault(_vault).set_accountant(accountant);

        HealthCheckAccountant(accountant).addVault(_vault);
    }

    /**
     * @dev Deploys a debt allocator for the specified vault.
     * @param _vault Address of the vault.
     * @return _debtAllocator Address of the deployed debt allocator.
     */
    function _deployAllocator(
        address _vault
    ) internal virtual returns (address _debtAllocator) {
        _debtAllocator = GenericDebtAllocatorFactory(allocatorFactory)
            .newGenericDebtAllocator(_vault);

        GenericDebtAllocator(_debtAllocator).setMaxAcceptableBaseFee(
            maxAcceptableBaseFee
        );

        // Give brain control of the debt allocator.
        GenericDebtAllocator(_debtAllocator).transferGovernance(
            roles[BRAIN]._address
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new vault to the RoleManager with the specified rating and debt allocator.
     * @dev If not already endorsed this function will endorse the vault.
     * @param _vault Address of the vault to be added.
     * @param _rating Rating associated with the vault.
     * @param _debtAllocator Address of the debt allocator for the vault.
     */
    function addNewVault(
        address _vault,
        uint256 _rating,
        address _debtAllocator
    ) external virtual onlyGovernance {
        IVault(_vault).accept_role_manager();

        (address _asset, , , , ) = Registry(registry).vaultInfo(_vault);
        if (_asset != address(0)) {
            Registry(registry).endorseMultiStrategyVault(_vault);
        }

        vaultConfig[_vault] = VaultConfig({
            asset: IVault(_vault).asset(),
            rating: _rating,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        vaults.push(_vault);
    }

    /**
     * @notice Removes a vault from the RoleManager.
     * @dev This will not un-endorse the vault.
     * @param _vault Address of the vault to be removed.
     */
    function removeVault(address _vault) external onlyGovernance {
        IVault(_vault).transfer_role_manager(role_manager_transfer);

        uint256 index = vaultConfig[_vault].index;
        address vaultToMove = vaults[vaults.length - 1];

        vaults[index] = vaultToMove;
        vaultConfig[vaultToMove].index = index;

        vaults.pop();

        delete vaultConfig[_vault];
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Setter function for updating a positions roles.
     * @param _position Identifier for the position.
     * @param _newRoles New roles for the position.
     */
    function adjustRole(
        bytes32 _position,
        uint256 _newRoles
    ) external onlyGovernance {
        roles[_position]._roles = uint96(_newRoles);
        emit UpdateRole(_position, _newRoles);
    }

    /**
     * @notice Setter function for updating a positions address.
     * @param _position Identifier for the position.
     * @param _newAddress New address for position.
     */
    function setPosition(
        bytes32 _position,
        address _newAddress
    ) external onlyGovernance {
        roles[_position]._address = _newAddress;
        emit UpdateAddress(_position, _newAddress);
    }

    /**
     * @notice Setter function for updating the accountant address.
     * @param _newAccountant New address for accountant.
     */
    function setAccountant(address _newAccountant) external onlyGovernance {
        accountant = _newAccountant;
        emit UpdateAddress(keccak256("Accountant"), _newAccountant);
    }

    /**
     * @notice Setter function for updating the registry address.
     * @param _newRegistry New address for registry.
     */
    function setRegistry(address _newRegistry) external onlyGovernance {
        registry = _newRegistry;
        emit UpdateAddress(keccak256("Registry"), _newRegistry);
    }

    /**
     * @notice Setter function for updating the allocatorFactory address.
     * @param _newAllocatorFactory New address for allocatorFactory.
     */
    function setAllocatorFactory(
        address _newAllocatorFactory
    ) external onlyGovernance {
        allocatorFactory = _newAllocatorFactory;
        emit UpdateAddress(keccak256("AllocatorFactory"), _newAllocatorFactory);
    }

    /**
     * @notice Sets the default time until profits are fully unlocked for new vaults.
     * @param _newDefaultProfitMaxUnlock New value for defaultProfitMaxUnlock.
     */
    function setDefaultProfitMaxUnlock(
        uint256 _newDefaultProfitMaxUnlock
    ) external onlyGovernance {
        defaultProfitMaxUnlock = _newDefaultProfitMaxUnlock;
        emit UpdateDefaultProfitMaxUnlock(_newDefaultProfitMaxUnlock);
    }

    /**
     * @notice Sets the maximum acceptable base fee for debt allocators.
     * @param _newMaxAcceptableBaseFee New value for maxAcceptableBaseFee.
     */
    function setMaxAcceptableBaseFee(
        uint256 _newMaxAcceptableBaseFee
    ) external onlyGovernance {
        maxAcceptableBaseFee = _newMaxAcceptableBaseFee;
        emit UpdateMaxAcceptableBaseFee(_newMaxAcceptableBaseFee);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getAllVaults() external view virtual returns (address[] memory) {
        return vaults;
    }
}
