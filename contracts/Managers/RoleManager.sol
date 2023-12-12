// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Roles} from "../libraries/Roles.sol";
import {Registry} from "../registry/Registry.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";
import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";
import {GenericDebtAllocatorFactory, GenericDebtAllocator} from "../debtAllocators/GenericDebtAllocatorFactory.sol";

/// @title Yearn V3 Vault Role Manager.
contract RoleManager is Governance2Step {
    /// @notice Emitted when a new address is set for a position.
    event UpdatePositionHolder(
        bytes32 indexed position,
        address indexed newAddress
    );

    /// @notice Emitted when a new set of roles is set for a position
    event UpdatePositionRoles(bytes32 indexed position, uint256 newRoles);

    /// @notice Emitted when the defaultProfitMaxUnlock variable is updated.
    event UpdateDefaultProfitMaxUnlock(uint256 newDefaultProfitMaxUnlock);

    /// @notice Emitted when the maxAcceptableBaseFee variable is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    /// @notice Emitted when a new vault has been deployed or added.
    event AddedNewVault(address indexed vault, uint256 rating);

    /// @notice Emitted when a vault is removed.
    event RemovedVault(address indexed vault);

    /// @notice Config that holds all vault info.
    struct VaultConfig {
        address asset;
        uint256 rating;
        address debtAllocator;
        uint256 index;
    }

    /// @notice Position struct
    struct Position {
        address holder;
        uint96 roles;
    }

    /// @notice Only allow either governance or the position holder to call.
    modifier onlyPositionHolder(bytes32 _positionId) {
        _isPositionHolder(_positionId);
        _;
    }

    /// @notice Check if the msg sender is governance or the specified position holder.
    function _isPositionHolder(bytes32 _positionId) internal view {
        require(
            msg.sender == governance ||
                msg.sender == getPositionHolder(_positionId),
            "!allowed"
        );
    }

    // Encoded name so that it can be held as a constant.
    bytes32 internal constant _name_ =
        bytes32(abi.encodePacked("Yearn V3 Vault Role Manager"));

    /*//////////////////////////////////////////////////////////////
                           POSITION ID'S
    //////////////////////////////////////////////////////////////*/

    /// @notice Position ID for "daddy".
    bytes32 public constant DADDY = keccak256("Daddy");
    /// @notice Position ID for "brain".
    bytes32 public constant BRAIN = keccak256("Brain");
    /// @notice Position ID for "keeper".
    bytes32 public constant KEEPER = keccak256("Keeper");
    /// @notice Position ID for "security".
    bytes32 public constant SECURITY = keccak256("Security");
    /// @notice Position ID for the Registry.
    bytes32 public constant REGISTRY = keccak256("Registry");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT = keccak256("Accountant");
    /// @notice Position ID for Debt Allocator
    bytes32 public constant DEBT_ALLOCATOR = keccak256("Debt Allocator");
    /// @notice Position ID for Strategy manager.
    bytes32 public constant STRATEGY_MANAGER = keccak256("Strategy Manager");
    /// @notice Position ID for the Allocator Factory.
    bytes32 public constant ALLOCATOR_FACTORY = keccak256("Allocator Factory");

    /// @notice Immutable address that the RoleManager position
    // will be transferred to when a vault is removed.
    address public immutable chad;

    /*//////////////////////////////////////////////////////////////
                           STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Array storing addresses of all managed vaults.
    address[] public vaults;

    /// @notice Mapping of position ID to position information.
    mapping(bytes32 => Position) internal _positions;
    /// @notice Mapping of a numerical rating to its string equivalent.
    mapping(uint256 => string) public ratingToString;
    /// @notice Mapping of vault addresses to its config.
    mapping(address => VaultConfig) public vaultConfig;

    /// @notice Default maximum acceptable base fee for debt allocators.
    uint256 public maxAcceptableBaseFee = 100e9;
    /// @notice Default time until profits are fully unlocked for new vaults.
    uint256 public defaultProfitMaxUnlock = 10 days;

    constructor(
        address _governance,
        address _daddy,
        address _brain,
        address _security,
        address _keeper,
        address _strategyManager
    ) Governance2Step(_governance) {
        require(_daddy != address(0), "ZERO ADDRESS");
        // Set the immutable address that will take over role manager
        // if a vault is removed.
        chad = _daddy;

        // Set up the initial role configs for each position.

        // Daddy is given all of the roles.
        _positions[DADDY] = Position({
            holder: _daddy,
            roles: uint96(Roles.ALL)
        });

        // Brain can process reports, update debt and adjust the queue.
        _positions[BRAIN] = Position({
            holder: _brain,
            roles: uint96(
                Roles.REPORTING_MANAGER |
                    Roles.DEBT_MANAGER |
                    Roles.QUEUE_MANAGER
            )
        });

        // Security cna set the max debt for strategies to have.
        _positions[SECURITY] = Position({
            holder: _security,
            roles: uint96(Roles.MAX_DEBT_MANAGER)
        });

        // The keeper can process reports and update debt.
        _positions[KEEPER] = Position({
            holder: _keeper,
            roles: uint96(Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER)
        });

        // Set just the roles for a debt allocator.
        _positions[DEBT_ALLOCATOR].roles = uint96(
            Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER
        );

        // The strategy manager can add and remove strategies.
        _positions[STRATEGY_MANAGER] = Position({
            holder: _strategyManager,
            roles: uint96(
                Roles.ADD_STRATEGY_MANAGER | Roles.REVOKE_STRATEGY_MANAGER
            )
        });

        // Set up the ratingToString mapping.
        ratingToString[1] = "A";
        ratingToString[2] = "B";
        ratingToString[3] = "C";
        ratingToString[4] = "D";
        ratingToString[5] = "F";
    }

    /*//////////////////////////////////////////////////////////////
                           VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new endorsed vault with default profit max
     *      unlock time and doesn't set the deposit limit.
     * @param _asset Address of the underlying asset.
     * @param _rating Rating of the vault.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _rating
    ) external virtual onlyPositionHolder(DADDY) returns (address) {
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
    ) external virtual onlyPositionHolder(DADDY) returns (address) {
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
    ) external virtual onlyPositionHolder(DADDY) returns (address) {
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

        // Create the name and symbol to be standardized based on rating.
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
        _vault = Registry(getPositionHolder(REGISTRY)).newEndorsedVault(
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

        // Emit event for new vault.
        emit AddedNewVault(_vault, _rating);
    }

    /**
     * @dev Deploys a debt allocator for the specified vault.
     * @param _vault Address of the vault.
     * @return _debtAllocator Address of the deployed debt allocator.
     */
    function _deployAllocator(
        address _vault
    ) internal virtual returns (address _debtAllocator) {
        address factory = getPositionHolder(ALLOCATOR_FACTORY);

        // If we have a factory set.
        if (factory != address(0)) {
            // Deploy a new debt allocator for the vault.
            _debtAllocator = GenericDebtAllocatorFactory(factory)
                .newGenericDebtAllocator(_vault);

            // Give Brain control of the debt allocator.
            GenericDebtAllocator(_debtAllocator).transferGovernance(
                getPositionHolder(BRAIN)
            );
        } else {
            // If no factory is set we should be using one central allocator.
            _debtAllocator = getPositionHolder(DEBT_ALLOCATOR);
        }
    }

    /**
     * @dev Assigns roles to the newly added vault.
     *
     * This will override any previously set roles for the holders. But not effect
     * the roles held by other addresses.
     *
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

        // Set the roles for the Strategy Manager.
        positionInfo = _positions[STRATEGY_MANAGER];
        IVault(_vault).set_role(
            positionInfo.holder,
            uint256(positionInfo.roles)
        );

        // Give the specific debt allocator its roles.
        positionInfo = _positions[DEBT_ALLOCATOR];
        IVault(_vault).set_role(_debtAllocator, uint256(positionInfo.roles));
    }

    /**
     * @dev Sets the accountant on the vault and adds the vault to the accountant.
     *   This temporarily gives the `ACCOUNTANT_MANAGER` role to this contract.
     * @param _vault Address of the vault to set up the accountant for.
     */
    function _setAccountant(address _vault) internal virtual {
        // Temporarily give this contract the ability to set the accountant.
        IVault(_vault).add_role(address(this), Roles.ACCOUNTANT_MANAGER);

        // Get the current accountant.
        address accountant = getPositionHolder(ACCOUNTANT);

        // Set the account on the vault.
        IVault(_vault).set_accountant(accountant);

        // Take away the role.
        IVault(_vault).remove_role(address(this), Roles.ACCOUNTANT_MANAGER);

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
        IVault(_vault).add_role(address(this), Roles.DEPOSIT_LIMIT_MANAGER);

        // Set the initial deposit limit on the vault.
        IVault(_vault).set_deposit_limit(_depositLimit);

        // Take away the role.
        IVault(_vault).remove_role(address(this), Roles.DEPOSIT_LIMIT_MANAGER);
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
    function addNewVault(address _vault, uint256 _rating) external virtual {
        address _debtAllocator = _deployAllocator(_vault);
        addNewVault(_vault, _rating, _debtAllocator);
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
    ) public virtual onlyPositionHolder(DADDY) {
        require(_rating > 0 && _rating < 6, "rating out of range");

        // If not the current role manager.
        if (IVault(_vault).role_manager() != address(this)) {
            // Accept the position of role manager.
            IVault(_vault).accept_role_manager();
        }

        // Get the current registry.
        address registry = getPositionHolder(REGISTRY);

        // Check if the vault has been endorsed yet in the registry.
        if (!Registry(registry).isEndorsed(_vault)) {
            // If not endorse it.
            Registry(registry).endorseMultiStrategyVault(_vault);
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

        // Emit event.
        emit AddedNewVault(_vault, _rating);
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
    ) public virtual onlyPositionHolder(DADDY) {
        // Make sure the vault has been added to the role manager.
        require(vaultConfig[_vault].asset != address(0), "vault not added");

        // Remove the roles from the old allocator.
        IVault(_vault).set_role(vaultConfig[_vault].debtAllocator, 0);

        // Give the new debt allocator the relevant roles.
        IVault(_vault).set_role(
            _debtAllocator,
            getPositionRoles(DEBT_ALLOCATOR)
        );

        // Update the vaults config.
        vaultConfig[_vault].debtAllocator = _debtAllocator;
    }

    /**
     * @notice Removes a vault from the RoleManager.
     * @dev This will NOT un-endorse the vault from the registry.
     * @param _vault Address of the vault to be removed.
     */
    function removeVault(
        address _vault
    ) external virtual onlyPositionHolder(DADDY) {
        // Make sure the vault has been added to the role manager.
        require(vaultConfig[_vault].asset != address(0), "vault not added");

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

        emit RemovedVault(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Setter function for updating a positions roles.
     * @param _position Identifier for the position.
     * @param _newRoles New roles for the position.
     */
    function setPositionRoles(
        bytes32 _position,
        uint256 _newRoles
    ) external virtual onlyGovernance {
        // Cannot change the debt allocator roles since it can be updated
        require(_position != DEBT_ALLOCATOR, "cannot update");
        _positions[_position].roles = uint96(_newRoles);

        emit UpdatePositionRoles(_position, _newRoles);
    }

    /**
     * @notice Setter function for updating a positions holder.
     * @param _position Identifier for the position.
     * @param _newHolder New address for position.
     */
    function setPositionHolder(
        bytes32 _position,
        address _newHolder
    ) external virtual onlyGovernance {
        _positions[_position].holder = _newHolder;

        emit UpdatePositionHolder(_position, _newHolder);
    }

    /**
     * @notice Sets the default time until profits are fully unlocked for new vaults.
     * @param _newDefaultProfitMaxUnlock New value for defaultProfitMaxUnlock.
     */
    function setDefaultProfitMaxUnlock(
        uint256 _newDefaultProfitMaxUnlock
    ) external virtual onlyGovernance {
        defaultProfitMaxUnlock = _newDefaultProfitMaxUnlock;

        emit UpdateDefaultProfitMaxUnlock(_newDefaultProfitMaxUnlock);
    }

    /**
     * @notice Sets the maximum acceptable base fee for debt allocators.
     * @param _newMaxAcceptableBaseFee New value for maxAcceptableBaseFee.
     */
    function setMaxAcceptableBaseFee(
        uint256 _newMaxAcceptableBaseFee
    ) external virtual onlyGovernance {
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
     * @notice Check if a vault is managed by this contract.
     * @dev This will check if the `asset` variable in the struct has been
     *   set for an easy external view check.
     *
     *   Does not check the vaults `role_manager` position since that can be set
     *   by anyone for a random vault.
     *
     * @param _vault Address of the vault to check.
     * @return . The vaults role manager status.
     */
    function isVaultsRoleManager(
        address _vault
    ) external view virtual returns (bool) {
        return vaultConfig[_vault].asset != address(0);
    }

    /**
     * @notice Get the debt allocator for a specific vault.
     * @dev Will return address(0) if the vault is not managed by this contract.
     * @param _vault Address of the vault.
     * @return . Address of the debt allocator if any.
     */
    function getDebtAllocator(
        address _vault
    ) external view virtual returns (address) {
        return vaultConfig[_vault].debtAllocator;
    }

    /**
     * @notice Get the rating for a specific vault.
     * @dev Will return 0 if the vault is not managed by this contract.
     * @param _vault Address of the vault.
     * @return . The rating of the vault if any.
     */
    function getRating(address _vault) external view virtual returns (uint256) {
        return vaultConfig[_vault].rating;
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
    function getPositionRoles(
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
     * @notice Get the address assigned to the strategy manager.
     * @return The address assigned to the strategy manager.
     */
    function getStrategyManager() external view virtual returns (address) {
        return getPositionHolder(STRATEGY_MANAGER);
    }

    /**
     * @notice Get the address assigned to the accountant.
     * @return The address assigned to the accountant.
     */
    function getAccountant() external view virtual returns (address) {
        return getPositionHolder(ACCOUNTANT);
    }

    /**
     * @notice Get the address assigned to the Registry.
     * @return The address assigned to the Registry.
     */
    function getRegistry() external view virtual returns (address) {
        return getPositionHolder(REGISTRY);
    }

    /**
     * @notice Get the address assigned to the allocator.
     * @return The address assigned to the allocator factory.
     */
    function getAllocatorFactory() external view virtual returns (address) {
        return getPositionHolder(ALLOCATOR_FACTORY);
    }

    /**
     * @notice Get the roles given to the Daddy position.
     * @return The roles given to the Daddy position.
     */
    function getDaddyRoles() external view virtual returns (uint256) {
        return getPositionRoles(DADDY);
    }

    /**
     * @notice Get the roles given to the Brain position.
     * @return The roles given to the Brain position.
     */
    function getBrainRoles() external view virtual returns (uint256) {
        return getPositionRoles(BRAIN);
    }

    /**
     * @notice Get the roles given to the Security position.
     * @return The roles given to the Security position.
     */
    function getSecurityRoles() external view virtual returns (uint256) {
        return getPositionRoles(SECURITY);
    }

    /**
     * @notice Get the roles given to the Keeper position.
     * @return The roles given to the Keeper position.
     */
    function getKeeperRoles() external view virtual returns (uint256) {
        return getPositionRoles(KEEPER);
    }

    /**
     * @notice Get the roles given to the debt allocators.
     * @return The roles given to the debt allocators.
     */
    function getDebtAllocatorRoles() external view virtual returns (uint256) {
        return getPositionRoles(DEBT_ALLOCATOR);
    }

    /**
     * @notice Get the roles given to the strategy manager.
     * @return The roles given to the strategy manager.
     */
    function getStrategyManagerRoles() external view virtual returns (uint256) {
        return getPositionRoles(STRATEGY_MANAGER);
    }
}
