// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {VaultConstants} from "@yearn-vaults/interfaces/VaultConstants.sol";

import {Registry} from "../registry/Registry.sol";
import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {GenericDebtAllocatorFactory, GenericDebtAllocator} from "../debtAllocators/GenericDebtAllocatorFactory.sol";

// add a strategy manager position to give add_strategy_manager

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

    struct Position {
        address holder;
        uint96 roles;
    }

    // Encoded name so that it can be held as a constant.
    bytes32 internal constant _name_ =
        bytes32(abi.encodePacked("Yearn V3 Vault Role Manager"));

    /// @notice Hash of the role name "daddy".
    bytes32 public constant DADDY = keccak256("Daddy");
    /// @notice Hash of the role name "brain".
    bytes32 public constant BRAIN = keccak256("Brain");
    /// @notice Hash of the role name "security".
    bytes32 public constant SECURITY = keccak256("Security");
    /// @notice Hash of the role name "keeper".
    bytes32 public constant KEEPER = keccak256("Keeper");

    /// @notice Immutable address that the RoleManager position
    // will be transferred to when a vault is removed.
    address public immutable chad;

    /// @notice Mapping of role hashes to role information.
    mapping(bytes32 => Position) internal _positions;
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
        chad = _daddy;

        // Set up the initial role configs for each position.

        // Daddy is given all of the roles.
        _positions[DADDY] = Position({holder: _daddy, roles: uint96(ALL)});

        // Brain can process reports, update debt and adjust the queue.
        _positions[BRAIN] = Position({
            holder: _brain,
            roles: uint96(REPORTING_MANAGER | DEBT_MANAGER | QUEUE_MANAGER)
        });

        // Security cna set the max debt for strategies to have.
        _positions[SECURITY] = Position({
            holder: _security,
            roles: uint96(MAX_DEBT_MANAGER)
        });

        // The keeper can process reports and update debt.
        _positions[KEEPER] = Position({
            holder: _keeper,
            roles: uint96(REPORTING_MANAGER | DEBT_MANAGER)
        });

        // Set up the ratingToString mapping.
        ratingToString[1] = "A";
        ratingToString[2] = "B";
        ratingToString[3] = "C";
        ratingToString[4] = "D";
        ratingToString[5] = "F";
    }

    /**
     * @notice Creates a new endorsed vault with default profit max
     *      unlock time and doesn't set the deposit limit.
     * @dev This is a permissionless function for anyone to deploy a vault
     *      that does not yet exist.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating
    ) external virtual returns (address) {
        return _newVault(_asset, _rating, 0, defaultProfitMaxUnlock);
    }

    /**
     * @notice Creates a new endorsed vault with default profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @param _depositLimit The deposit limit to start the vault with.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating,
        uint256 _depositLimit
    ) external virtual onlyGovernance returns (address) {
        return
            _newVault(_asset, _rating, _depositLimit, defaultProfitMaxUnlock);
    }

    /**
     * @notice Creates a new endorsed vault.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @param _depositLimit The deposit limit to start the vault with.
     * @param _profitMaxUnlockTime Time until profits are fully unlocked.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating,
        uint256 _depositLimit,
        uint256 _profitMaxUnlockTime
    ) external virtual onlyGovernance returns (address) {
        return _newVault(_asset, _rating, _depositLimit, _profitMaxUnlockTime);
    }

    /**
     * @notice Creates a new endorsed vault.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @param _depositLimit The deposit limit to start the vault with.
     * @param _profitMaxUnlockTime Time until profits are fully unlocked.
     * @return _vault Address of the newly created vault.
     */
    function _newVault(
        address _asset,
        uint256 _rating,
        uint256 _depositLimit,
        uint256 _profitMaxUnlockTime
    ) internal virtual returns (address _vault) {
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

        // Deploy a new debt allocator for the vault.
        address _debtAllocator = _deployAllocator(_vault);

        // Give out roles on the new vault.
        _sanctify(_vault, _debtAllocator);

        // Set up the accountant.
        _setAccountant(_vault);

        if (_depositLimit != 0) {
            _setDepositLimit(_vault, _depositLimit);
        }

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
     * @dev Deploys a debt allocator for the specified vault.
     * @param _vault Address of the vault.
     * @return _debtAllocator Address of the deployed debt allocator.
     */
    function _deployAllocator(
        address _vault
    ) internal virtual returns (address _debtAllocator) {
        // Deploy a new debt allocator for the vault.
        _debtAllocator = GenericDebtAllocatorFactory(allocatorFactory)
            .newGenericDebtAllocator(_vault);

        // Set the default max base fee.
        GenericDebtAllocator(_debtAllocator).setMaxAcceptableBaseFee(
            maxAcceptableBaseFee
        );

        // Give Brain control of the debt allocator.
        GenericDebtAllocator(_debtAllocator).transferGovernance(
            getPositionHolder(BRAIN)
        );
    }

    /**
     * @dev Assigns roles to the newly created vault and performs additional configurations.
     *      This will override any previously set roles for the addresses. But not effect
     *      the roles held by other addresses.
     * @param _vault Address of the vault to sanctify.
     * @param _debtAllocator Address of the debt allocator for the vault.
     */
    function _sanctify(
        address _vault,
        address _debtAllocator
    ) internal virtual {
        // Cache positionInfo to be reused for each setter.
        Position memory positionInfo = _positions[DADDY];

        // Set the roles for daddy.
        IVault(_vault).set_role(
            positionInfo.holder,
            uint256(positionInfo.roles)
        );

        // Set the roles for Brain.
        positionInfo = _positions[BRAIN];
        IVault(_vault).set_role(
            positionInfo.holder,
            uint256(positionInfo.roles)
        );

        // Set the roles for Security.
        positionInfo = _positions[SECURITY];
        IVault(_vault).set_role(
            positionInfo.holder,
            uint256(positionInfo.roles)
        );

        // Set the roles for the Keeper.
        positionInfo = _positions[KEEPER];
        IVault(_vault).set_role(
            positionInfo.holder,
            uint256(positionInfo.roles)
        );

        // Let the debt allocator manage debt.
        IVault(_vault).set_role(_debtAllocator, DEBT_MANAGER);
    }

    /**
     * @dev Sets the accountant on the vault and adds the vault to the accountant.
     *   This temporarily gives the `ACCOUNTANT_MANAGER` role to this contract.
     * @param _vault Address of the vault to set up the accountant for.
     */
    function _setAccountant(address _vault) internal virtual {
        // Temporarily give this contract the ability to set the accountant.
        IVault(_vault).add_role(address(this), ACCOUNTANT_MANAGER);

        // Set the account on the vault.
        IVault(_vault).set_accountant(accountant);

        // Take away the role.
        IVault(_vault).remove_role(address(this), ACCOUNTANT_MANAGER);

        // Whitelist the vault in the accountant.
        HealthCheckAccountant(accountant).addVault(_vault);
    }

    /**
     * @dev Used to set an initial deposit limit when a new vault is deployed.
     *   Any further updates to the limit will need to be done by an address that
     *   holds the `DEPOSIT_LIMIT_MANAGER` role.
     * @param _vault Address of the newly deployed vault.
     * @param _depositLimit The deposit limit to set.
     */
    function _setDepositLimit(
        address _vault,
        uint256 _depositLimit
    ) internal virtual {
        // Temporarily give this contract the ability to set the deposit limit.
        IVault(_vault).add_role(address(this), DEPOSIT_LIMIT_MANAGER);

        // Set the initial deposit limit on the vault.
        IVault(_vault).set_deposit_limit(_depositLimit);

        // Take away the role.
        IVault(_vault).remove_role(address(this), DEPOSIT_LIMIT_MANAGER);
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

        // If there is no existing debt allocator.
        if (_debtAllocator == address(0)) {
            // Deploy a new one.
            _debtAllocator = _deployAllocator(_vault);
        }

        // Set the roles up.
        _sanctify(_vault, _debtAllocator);

        // Only set an accountant if there is not one set yet.
        if (IVault(_vault).accountant() == address(0)) {
            _setAccountant(_vault);
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
     * @notice Update a `_vault`s debt allocator.
     * @dev This will deploy a new allocator using the current
     *   allocator factory set.
     * @param _vault Address of the vault to update the allocator for.
     */
    function updateDebtAllocator(
        address _vault
    ) external virtual returns (address _newDebtAllocator) {
        _newDebtAllocator = _deployAllocator(_vault);
        updateDebtAllocator(_vault, _newDebtAllocator);
    }

    /**
     * @notice Update a `_vault`s debt allocator to a specified `_debtAllocator`.
     * @param _vault Address of the vault to update the allocator for.
     * @param _debtAllocator Address of the new debt allocator.
     */
    function updateDebtAllocator(
        address _vault,
        address _debtAllocator
    ) public virtual onlyGovernance {
        require(vaultConfig[_vault].asset != address(0), "vault not added");

        // Give the new debt allocator the debt manager role.
        IVault(_vault).add_role(_debtAllocator, DEBT_MANAGER);

        // Update the vaults config.
        vaultConfig[_vault].debtAllocator = _debtAllocator;
    }

    /**
     * @notice Removes a vault from the RoleManager.
     * @dev This will NOT un-endorse the vault.
     * @param _vault Address of the vault to be removed.
     */
    function removeVault(address _vault) external virtual onlyGovernance {
        // Transfer the role manager position.
        IVault(_vault).transfer_role_manager(chad);

        // Index that the vault is in the array.
        uint256 index = vaultConfig[_vault].index;
        // Address of the vault to replace it with.
        address vaultToMove = vaults[vaults.length - 1];

        // Move the last vault to the index of `_vault`
        vaults[index] = vaultToMove;
        vaultConfig[vaultToMove].index = index;

        // Remove the last item.
        vaults.pop();

        // Delete the config for `_vault`.
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
        _positions[_position].roles = uint96(_newRoles);
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
        _positions[_position].holder = _newAddress;
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
     * @notice Get the address and roles given to a specific position.
     * @param _positionId The position identifier.
     * @return The address that holds that position.
     * @return The roles given to the specified position.
     */
    function getPosition(
        bytes32 _positionId
    ) public view virtual returns (address, uint256) {
        Position memory _position = _positions[_positionId];
        return (_position.holder, uint256(_position.roles));
    }

    /**
     * @notice Get the current address assigned to a specific position.
     * @param _positionId The position identifier.
     * @return The current address assigned to the specified position.
     */
    function getPositionHolder(
        bytes32 _positionId
    ) public view virtual returns (address) {
        return _positions[_positionId].holder;
    }

    /**
     * @notice Get the current roles given to a specific position ID.
     * @param _positionId The position identifier.
     * @return The current roles given to the specified position ID.
     */
    function getCurrentRoles(
        bytes32 _positionId
    ) public view virtual returns (uint256) {
        return uint256(_positions[_positionId].roles);
    }

    /**
     * @notice Get the address assigned to the Daddy position.
     * @return The address assigned to the Daddy position.
     */
    function getDaddy() external view virtual returns (address) {
        return getPositionHolder(DADDY);
    }

    /**
     * @notice Get the address assigned to the Brain position.
     * @return The address assigned to the Brain position.
     */
    function getBrain() external view virtual returns (address) {
        return getPositionHolder(BRAIN);
    }

    /**
     * @notice Get the address assigned to the Security position.
     * @return The address assigned to the Security position.
     */
    function getSecurity() external view virtual returns (address) {
        return getPositionHolder(SECURITY);
    }

    /**
     * @notice Get the address assigned to the Keeper position.
     * @return The address assigned to the Keeper position.
     */
    function getKeeper() external view virtual returns (address) {
        return getPositionHolder(KEEPER);
    }

    /**
     * @notice Get the roles given to the Daddy position.
     * @return The roles given to the Daddy position.
     */
    function getDaddyRoles() external view virtual returns (uint256) {
        return getCurrentRoles(DADDY);
    }

    /**
     * @notice Get the roles given to the Brain position.
     * @return The roles given to the Brain position.
     */
    function getBrainRoles() external view virtual returns (uint256) {
        return getCurrentRoles(BRAIN);
    }

    /**
     * @notice Get the roles given to the Security position.
     * @return The roles given to the Security position.
     */
    function getSecurityRoles() external view virtual returns (uint256) {
        return getCurrentRoles(SECURITY);
    }

    /**
     * @notice Get the roles given to the Keeper position.
     * @return The roles given to the Keeper position.
     */
    function getKeeperRoles() external view virtual returns (uint256) {
        return getCurrentRoles(KEEPER);
    }

    // This fallback will forward any undefined function calls to the Registry.
    // This allows for both read and write functions to only need to interact
    // with one address.
    // NOTE: Both contracts share the `governance` contract functions and {name}.
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
