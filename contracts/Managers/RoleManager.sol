// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstants} from "@yearn-vaults/interfaces/VaultConstants.sol";

import {Registry} from "../registry/Registry.sol";
import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {GenericDebtAllocatorFactory, GenericDebtAllocator} from "../debtAllocators/GenericDebtAllocatorFactory.sol";

/// @title Yearn V3 vault Role Manager.
contract RoleManager is Governance2Step, VaultConstants {
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

    // Encoded name so that it can be held as a constant.
    bytes32 internal constant _name_ =
        bytes32(abi.encodePacked("Yearn V3 Vault Role Manager"));

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
    /// @notice Mapping of a numerical rating to its string equivalent.
    mapping(uint256 => string) public ratingToString;

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
        address _governance,
        address _daddy,
        address _brain,
        address _keeper,
        address _security
    ) Governance2Step(_governance) {
        // Set the immutable address that will take over role manager
        // if a vault is removed.
        role_manager_transfer = _daddy;

        // Set up the initial role configs for each position.

        // Daddy is given all of the roles.
        roles[DADDY] = Roles({_address: _daddy, _roles: uint96(ALL)});

        // Brain can process reports, update debt and adjust the queue.
        roles[BRAIN] = Roles({
            _address: _brain,
            _roles: uint96(REPORTING_MANAGER | DEBT_MANAGER | QUEUE_MANAGER)
        });

        // Security cna set the max debt for strategies to have.
        roles[SECURITY] = Roles({
            _address: _security,
            _roles: uint96(MAX_DEBT_MANAGER)
        });

        // The keeper can process reports and update debt.
        roles[KEEPER] = Roles({
            _address: _keeper,
            _roles: uint96(REPORTING_MANAGER | DEBT_MANAGER)
        });

        // Set up the ratingToString mapping.
        ratingToString[1] = "A";
        ratingToString[2] = "B";
        ratingToString[3] = "C";
        ratingToString[4] = "D";
        ratingToString[5] = "F";
    }

    /**
     * @notice Creates a new endorsed vault with default profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating
    ) external virtual returns (address) {
        return newVault(_asset, _rating, defaultProfitMaxUnlock);
    }

    /**
     * @notice Creates a new endorsed vault with specified profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @param _profitMaxUnlockTime Time until profits are fully unlocked.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating,
        uint256 _profitMaxUnlockTime
    ) public virtual onlyGovernance returns (address _vault) {
        require(_rating > 0 && _rating < 6, "rating out of range");

        // Create the name and string to be standardized based on rating.
        string memory ratingString = ratingToString[_rating];
        // Name is "{SYMBOL} yVault-{RATING}"
        string memory _name = string(
            abi.encodePacked(ERC20(_asset).symbol(), " yVault-", ratingString)
        );
        // Symbol is "yv{SYMBOL}-{RATING}".
        string memory _symbol = string(
            abi.encodePacked("yv", ERC20(_asset).symbol(), "-", ratingString)
        );

        // Deploy through the registry so it is automatically endorsed.
        _vault = Registry(registry).newEndorsedVault(
            _asset,
            _name,
            _symbol,
            address(this),
            _profitMaxUnlockTime
        );

        // Give out roles on the new vault.
        _sanctify(_vault);

        // Deploy a new debt allocator for the vault.
        address _debtAllocator = _deployAllocator(_vault);

        // Add the vault config to the mapping.
        vaultConfig[_vault] = VaultConfig({
            asset: _asset,
            rating: _rating,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        // Add the vault to the array.
        vaults.push(_vault);
    }

    /**
     * @dev Assigns roles to the newly created vault and performs additional configurations.
     * @param _vault Address of the vault to sanctify.
     */
    function _sanctify(address _vault) internal virtual {
        // Cache roleInfo to be reused for each setter.
        Roles memory roleInfo = roles[DADDY];

        // Set the roles for daddy.
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[BRAIN];
        // Set the roles for Brain.
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[SECURITY];
        // Set the roles for security.
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        roleInfo = roles[KEEPER];
        // Set the roles for the Keeper.
        IVault(_vault).set_role(roleInfo._address, uint256(roleInfo._roles));

        // Set the account on the vault.
        IVault(_vault).set_accountant(accountant);

        // Whitelist the vault in the accountant.
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
        GenericDebtAllocator(_debtAllocator).transferGovernance(getBrain());
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new vault to the RoleManager with the specified rating.
     * @dev If not already endorsed this function will endorse the vault.
     *  A new debt allocator will be deployed and configured.
     * @param _vault Address of the vault to be added.
     * @param _rating Rating associated with the vault.
     */
    function addNewVault(
        address _vault,
        uint256 _rating
    ) external virtual onlyGovernance {
        addNewVault(_vault, _rating, address(0));
    }

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
    ) public virtual onlyGovernance {
        // If not the current role manager.
        if (IVault(_vault).role_manager() != address(this)) {
            // Accept the position of role manager.
            IVault(_vault).accept_role_manager();
        }

        // Check if the vault has been endorsed yet in the registry,
        (address _asset, , , , ) = Registry(registry).vaultInfo(_vault);
        if (_asset != address(0)) {
            // If not endorse it.
            Registry(registry).endorseMultiStrategyVault(_vault);
        }

        // Set the roles up.
        _sanctify(_vault);

        // If there is no existing debt allocator.
        if (_debtAllocator == address(0)) {
            // Deploy a new one.
            _debtAllocator = _deployAllocator(_vault);
        }

        // Add the vault config to the mapping.
        vaultConfig[_vault] = VaultConfig({
            asset: IVault(_vault).asset(),
            rating: _rating,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        // Add the vault to the array.
        vaults.push(_vault);
    }

    /**
     * @notice Removes a vault from the RoleManager.
     * @dev This will NOT un-endorse the vault.
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

    /**
     * @notice Get the name of this contract.
     */
    function name() external view virtual returns (string memory) {
        return string(abi.encodePacked(_name_));
    }

    /**
     * @notice Get all vaults that this role manager controls..
     * @return The full array of vault addresses.
     */
    function getAllVaults() external view virtual returns (address[] memory) {
        return vaults;
    }

    /**
     * @notice Get the address and roles held for a specific role.
     * @param _roleId The role identifier.
     * @return The address that holds that position.
     * @return The roles held for the specified role.
     */
    function getRole(
        bytes32 _roleId
    ) public view virtual returns (address, uint256) {
        Roles memory _role = roles[_roleId];
        return (_role._address, uint256(_role._roles));
    }

    /**
     * @notice Get the current address assigned to a specific role.
     * @param _roleId The role identifier.
     * @return The current address assigned to the specified role.
     */
    function getCurrentRole(
        bytes32 _roleId
    ) public view virtual returns (address) {
        return roles[_roleId]._address;
    }

    /**
     * @notice Get the current roles held for a specific role ID.
     * @param _roleId The role identifier.
     * @return The current roles held for the specified role ID.
     */
    function getCurrentRolesHeld(
        bytes32 _roleId
    ) public view virtual returns (uint256) {
        return uint256(roles[_roleId]._roles);
    }

    /**
     * @notice Get the address assigned to the Daddy role.
     * @return The address assigned to the Daddy role.
     */
    function getDaddy() public view virtual returns (address) {
        return getCurrentRole(DADDY);
    }

    /**
     * @notice Get the address assigned to the Brain role.
     * @return The address assigned to the Brain role.
     */
    function getBrain() public view virtual returns (address) {
        return getCurrentRole(BRAIN);
    }

    /**
     * @notice Get the address assigned to the Security role.
     * @return The address assigned to the Security role.
     */
    function getSecurity() public view virtual returns (address) {
        return getCurrentRole(SECURITY);
    }

    /**
     * @notice Get the address assigned to the Keeper role.
     * @return The address assigned to the Keeper role.
     */
    function getKeeper() public view virtual returns (address) {
        return getCurrentRole(KEEPER);
    }

    /**
     * @notice Get the roles held for the Daddy role.
     * @return The roles held for the Daddy role.
     */
    function getDaddyRoles() public view virtual returns (uint256) {
        return getCurrentRolesHeld(DADDY);
    }

    /**
     * @notice Get the roles held for the Brain role.
     * @return The roles held for the Brain role.
     */
    function getBrainRoles() public view virtual returns (uint256) {
        return getCurrentRolesHeld(BRAIN);
    }

    /**
     * @notice Get the roles held for the Security role.
     * @return The roles held for the Security role.
     */
    function getSecurityRoles() public view virtual returns (uint256) {
        return getCurrentRolesHeld(SECURITY);
    }

    /**
     * @notice Get the roles held for the Keeper role.
     * @return The roles held for the Keeper role.
     */
    function getKeeperRoles() public view virtual returns (uint256) {
        return getCurrentRolesHeld(KEEPER);
    }

    // This fallback will forward any undefined function calls to the Registry.
    // This allows for both read and write functions to only need to interact
    // with one address.
    // NOTE: Both contracts share the {governance} and {name} functions.
    fallback() external {
        // load our target address
        address _registry = registry;
        // Execute external function using delegatecall and return any value.
        assembly {
            // Copy function selector and any arguments.
            calldatacopy(0, 0, calldatasize())
            // Execute function delegatecall.
            let result := delegatecall(
                gas(),
                _registry,
                0,
                calldatasize(),
                0,
                0
            )
            // Get any return value
            returndatacopy(0, 0, returndatasize())
            // Return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
