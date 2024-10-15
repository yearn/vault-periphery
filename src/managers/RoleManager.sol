// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Positions} from "./Positions.sol";
import {Registry} from "../registry/Registry.sol";
import {Accountant} from "../accountants/Accountant.sol";
import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {ReleaseRegistry} from "../registry/ReleaseRegistry.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

/// @title Yearn V3 Vault Role Manager.
contract RoleManager is Positions {
    /// @notice Revert message for when a vault has already been deployed.
    error AlreadyDeployed(address _vault);

    /// @notice Emitted when a new vault has been deployed or added.
    event AddedNewVault(
        address indexed vault,
        address indexed debtAllocator,
        uint256 category
    );

    /// @notice Emitted when a vaults debt allocator is updated.
    event UpdateDebtAllocator(
        address indexed vault,
        address indexed debtAllocator
    );

    /// @notice Emitted when a vault is removed.
    event RemovedVault(address indexed vault);

    /// @notice Emitted when the defaultProfitMaxUnlockTime variable is updated.
    event UpdateDefaultProfitMaxUnlockTime(
        uint256 newDefaultProfitMaxUnlockTime
    );

    /// @notice Config that holds all vault info.
    struct VaultConfig {
        address asset;
        uint256 category;
        address debtAllocator;
        uint256 index;
    }

    /*//////////////////////////////////////////////////////////////
                           POSITION ID'S
    //////////////////////////////////////////////////////////////*/

    /// @notice Position ID for "Pending Governance".
    bytes32 public constant PENDING_GOVERNANCE =
        keccak256("Pending Governance");
    /// @notice Position ID for "Governance".
    bytes32 public constant GOVERNANCE = keccak256("Governance");
    /// @notice Position ID for "brain".
    bytes32 public constant MANAGEMENT = keccak256("Management");

    /// @notice Position ID for "keeper".
    bytes32 public constant KEEPER = keccak256("Keeper");
    /// @notice Position ID for the Registry.
    bytes32 public constant REGISTRY = keccak256("Registry");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT = keccak256("Accountant");
    /// @notice Position ID for Debt Allocator
    bytes32 public constant DEBT_ALLOCATOR = keccak256("Debt Allocator");

    /*//////////////////////////////////////////////////////////////
                           STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Immutable address that the `role_manager` position
    // will be transferred to when a vault is removed.
    address public chad;

    /// @notice Array storing addresses of all managed vaults.
    address[] public vaults;

    // Encoded name so that it can be held as a constant.
    string internal projectName;

    /// @notice Default time until profits are fully unlocked for new vaults.
    uint256 public defaultProfitMaxUnlockTime;

    /// @notice Mapping of vault addresses to its config.
    mapping(address => VaultConfig) public vaultConfig;

    /// @notice Mapping of underlying asset, api version and category to vault.
    mapping(address => mapping(string => mapping(uint256 => address)))
        internal _assetToVault;

    constructor() {
        chad = address(1);
    }

    function initialize(
        string calldata _projectName,
        address _governance,
        address _management,
        address _keeper,
        address _registry,
        address _accountant,
        address _debtAllocator
    ) external {
        require(chad == address(0), "initialized");
        require(_governance != address(0), "ZERO ADDRESS");

        chad = _governance;
        projectName = _projectName;
        defaultProfitMaxUnlockTime = 10 days;

        // Governance gets all the roles.
        _setPositionHolder(GOVERNANCE, _governance);
        _setPositionRoles(GOVERNANCE, Roles.ALL);

        // Management reports, can update debt, queue, deposit limits and unlock time.
        _setPositionHolder(MANAGEMENT, _management);
        _setPositionRoles(
            MANAGEMENT,
            Roles.REPORTING_MANAGER |
                Roles.DEBT_MANAGER |
                Roles.QUEUE_MANAGER |
                Roles.DEPOSIT_LIMIT_MANAGER |
                Roles.DEBT_PURCHASER |
                Roles.PROFIT_UNLOCK_MANAGER
        );

        // The keeper can process reports.
        _setPositionHolder(KEEPER, _keeper);
        _setPositionRoles(KEEPER, Roles.REPORTING_MANAGER);

        // Debt allocators manage debt and also need to process reports.
        _setPositionHolder(DEBT_ALLOCATOR, _debtAllocator);
        _setPositionRoles(
            DEBT_ALLOCATOR,
            Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER
        );

        _setPositionHolder(REGISTRY, _registry);
        _setPositionHolder(ACCOUNTANT, _accountant);
    }

    /*//////////////////////////////////////////////////////////////
                           VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new endorsed vault with default profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _category Category of the vault.
     * @param _name Name of the vault.
     * @param _symbol Symbol of the vault.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _category,
        string calldata _name,
        string calldata _symbol
    ) external virtual onlyPositionHolder(GOVERNANCE) returns (address) {
        return _newVault(_asset, _category, _name, _symbol, type(uint256).max);
    }

    /**
     * @notice Creates a new endorsed vault with default profit max unlock time.
     * @param _asset Address of the underlying asset.
     * @param _category Category of the vault.
     * @param _name Name of the vault.
     * @param _symbol Symbol of the vault.
     * @param _depositLimit The deposit limit to start the vault with.
     * @return _vault Address of the newly created vault.
     */
    function newVault(
        address _asset,
        uint256 _category,
        string calldata _name,
        string calldata _symbol,
        uint256 _depositLimit
    ) external virtual onlyPositionHolder(GOVERNANCE) returns (address) {
        return _newVault(_asset, _category, _name, _symbol, _depositLimit);
    }

    /**
     * @notice Creates a new endorsed vault.
     * @param _asset Address of the underlying asset.
     * @param _category Category of the vault.
     * @param _name Name of the vault.
     * @param _symbol Symbol of the vault.
     * @param _depositLimit The deposit limit to start the vault with.
     * @return _vault Address of the newly created vault.
     */
    function _newVault(
        address _asset,
        uint256 _category,
        string memory _name,
        string memory _symbol,
        uint256 _depositLimit
    ) internal virtual returns (address _vault) {
        // Deploy through the registry so it is automatically endorsed.
        _vault = Registry(getPositionHolder(REGISTRY)).newEndorsedVault(
            _asset,
            _name,
            _symbol,
            address(this),
            defaultProfitMaxUnlockTime
        );

        // Check that a vault does not exist for that asset, api and category.
        // This reverts late to not waste gas when used correctly.
        string memory _apiVersion = IVault(_vault).apiVersion();
        if (_assetToVault[_asset][_apiVersion][_category] != address(0)) {
            revert AlreadyDeployed(
                _assetToVault[_asset][_apiVersion][_category]
            );
        }

        address _debtAllocator = getPositionHolder(DEBT_ALLOCATOR);
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
            category: _category,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        // Add the vault to the mapping.
        _assetToVault[_asset][_apiVersion][_category] = _vault;

        // Add the vault to the array.
        vaults.push(_vault);

        // Emit event for new vault.
        emit AddedNewVault(_vault, _debtAllocator, _category);
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
        // Set the roles for daddy.
        _setRole(_vault, _positions[GOVERNANCE]);

        // Set the roles for Management.
        _setRole(_vault, _positions[MANAGEMENT]);

        // Set the roles for the Keeper.
        _setRole(_vault, _positions[KEEPER]);

        // Give the specific debt allocator its roles.
        _setRole(
            _vault,
            Position(_debtAllocator, _positions[DEBT_ALLOCATOR].roles)
        );
    }

    /**
     * @dev Used internally to set the roles on a vault for a given position.
     *   Will not set the roles if the position holder is address(0).
     *   This does not check that the roles are !=0 because it is expected that
     *   the holder will be set to 0 if the position is not being used.
     *
     * @param _vault Address of the vault.
     * @param _position Holder address and roles to set.
     */
    function _setRole(
        address _vault,
        Position memory _position
    ) internal virtual {
        if (_position.holder != address(0)) {
            IVault(_vault).set_role(_position.holder, uint256(_position.roles));
        }
    }

    /**
     * @dev Sets the accountant on the vault and adds the vault to the accountant.
     *   This temporarily gives the `ACCOUNTANT_MANAGER` role to this contract.
     * @param _vault Address of the vault to set up the accountant for.
     */
    function _setAccountant(address _vault) internal virtual {
        // Get the current accountant.
        address accountant = getPositionHolder(ACCOUNTANT);

        // If there is an accountant set.
        if (accountant != address(0)) {
            // Temporarily give this contract the ability to set the accountant.
            IVault(_vault).add_role(address(this), Roles.ACCOUNTANT_MANAGER);

            // Set the account on the vault.
            IVault(_vault).set_accountant(accountant);

            // Take away the role.
            IVault(_vault).remove_role(address(this), Roles.ACCOUNTANT_MANAGER);

            // Whitelist the vault in the accountant.
            Accountant(accountant).addVault(_vault);
        }
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
     * @notice Adds a new vault to the RoleManager with the specified category.
     * @dev If not already endorsed this function will endorse the vault.
     *  A new debt allocator will be deployed and configured.
     * @param _vault Address of the vault to be added.
     * @param _category Category associated with the vault.
     */
    function addNewVault(address _vault, uint256 _category) external virtual {
        addNewVault(_vault, _category, getPositionHolder(DEBT_ALLOCATOR));
    }

    /**
     * @notice Adds a new vault to the RoleManager with the specified category and debt allocator.
     * @dev If not already endorsed this function will endorse the vault.
     * @param _vault Address of the vault to be added.
     * @param _category Category associated with the vault.
     * @param _debtAllocator Address of the debt allocator for the vault.
     */
    function addNewVault(
        address _vault,
        uint256 _category,
        address _debtAllocator
    ) public virtual onlyPositionHolder(GOVERNANCE) {
        // Check that a vault does not exist for that asset, api and category.
        address _asset = IVault(_vault).asset();
        string memory _apiVersion = IVault(_vault).apiVersion();
        if (_assetToVault[_asset][_apiVersion][_category] != address(0)) {
            revert AlreadyDeployed(
                _assetToVault[_asset][_apiVersion][_category]
            );
        }

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
            // NOTE: This will revert if adding a vault of an older version.
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
            asset: _asset,
            category: _category,
            debtAllocator: _debtAllocator,
            index: vaults.length
        });

        // Add the vault to the mapping.
        _assetToVault[_asset][_apiVersion][_category] = _vault;

        // Add the vault to the array.
        vaults.push(_vault);

        // Emit event.
        emit AddedNewVault(_vault, _debtAllocator, _category);
    }

    /**
     * @notice Update a `_vault`s debt allocator.
     * @dev This will use the default Debt Allocator currently set.
     * @param _vault Address of the vault to update the allocator for.
     */
    function updateDebtAllocator(
        address _vault
    ) external virtual returns (address _newDebtAllocator) {
        _newDebtAllocator = getPositionHolder(DEBT_ALLOCATOR);
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
    ) public virtual onlyPositionHolder(MANAGEMENT) {
        // Make sure the vault has been added to the role manager.
        require(vaultConfig[_vault].asset != address(0), "vault not added");

        // Remove the roles from the old allocator.
        _setRole(_vault, Position(vaultConfig[_vault].debtAllocator, 0));

        // Give the new debt allocator the relevant roles.
        _setRole(
            _vault,
            Position(_debtAllocator, _positions[DEBT_ALLOCATOR].roles)
        );

        // Update the vaults config.
        vaultConfig[_vault].debtAllocator = _debtAllocator;

        // Emit event.
        emit UpdateDebtAllocator(_vault, _debtAllocator);
    }

    /**
     * @notice Update a `_vault`s keeper to a specified `_keeper`.
     * @param _vault Address of the vault to update the keeper for.
     * @param _keeper Address of the new keeper.
     */
    function updateKeeper(
        address _vault,
        address _keeper
    ) external virtual onlyPositionHolder(MANAGEMENT) {
        // Make sure the vault has been added to the role manager.
        require(vaultConfig[_vault].asset != address(0), "vault not added");

        // Remove the roles from the old keeper if active.
        address defaultKeeper = getPositionHolder(KEEPER);
        if (
            _keeper != defaultKeeper && IVault(_vault).roles(defaultKeeper) != 0
        ) {
            _setRole(_vault, Position(defaultKeeper, 0));
        }

        // Give the new keeper the relevant roles.
        _setRole(_vault, Position(_keeper, _positions[KEEPER].roles));
    }

    function updateVaultName(
        address _vault,
        string calldata _name
    ) external onlyPositionHolder(GOVERNANCE) {
        require(vaultConfig[_vault].asset != address(0), "vault not added");
        IVault(_vault).setName(_name);
    }

    function updateVaultSymbol(
        address _vault,
        string calldata _symbol
    ) external onlyPositionHolder(GOVERNANCE) {
        require(vaultConfig[_vault].asset != address(0), "vault not added");
        IVault(_vault).setSymbol(_symbol);
    }

    /**
     * @notice Removes a vault from the RoleManager.
     * @dev This will NOT un-endorse the vault from the registry.
     * @param _vault Address of the vault to be removed.
     */
    function removeVault(
        address _vault
    ) external virtual onlyPositionHolder(MANAGEMENT) {
        // Get the vault specific config.
        VaultConfig memory config = vaultConfig[_vault];
        // Make sure the vault has been added to the role manager.
        require(config.asset != address(0), "vault not added");

        // Transfer the role manager position.
        IVault(_vault).transfer_role_manager(chad);

        // Address of the vault to replace it with.
        address vaultToMove = vaults[vaults.length - 1];

        // Move the last vault to the index of `_vault`
        vaults[config.index] = vaultToMove;
        vaultConfig[vaultToMove].index = config.index;

        // Remove the last item.
        vaults.pop();

        // Delete the vault from the mapping.
        delete _assetToVault[config.asset][IVault(_vault).apiVersion()][
            config.category
        ];

        // Delete the config for `_vault`.
        delete vaultConfig[_vault];

        emit RemovedVault(_vault);
    }

    /**
     * @notice Removes a specific role(s) for a `_holder` from the `_vaults`.
     * @dev Can be used to remove one specific role or multiple.
     * @param _vaults Array of vaults to adjust.
     * @param _holder Address who's having a role removed.
     * @param _role The role or roles to remove from the `_holder`.
     */
    function removeRoles(
        address[] calldata _vaults,
        address _holder,
        uint256 _role
    ) external virtual onlyPositionHolder(GOVERNANCE) {
        address _vault;
        for (uint256 i = 0; i < _vaults.length; ++i) {
            _vault = _vaults[i];
            // Make sure the vault is added to this Role Manager.
            require(vaultConfig[_vault].asset != address(0), "vault not added");

            // Remove the role.
            IVault(_vault).remove_role(_holder, _role);
        }
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
    ) external virtual onlyPositionHolder(GOVERNANCE) {
        // Cannot change the debt allocator or keeper roles since holder can be updated.
        require(
            _position != DEBT_ALLOCATOR && _position != KEEPER,
            "cannot update"
        );
        _setPositionRoles(_position, _newRoles);
    }

    /**
     * @notice Setter function for updating a positions holder.
     * @dev Updating `Governance` requires setting `PENDING_GOVERNANCE`
     *  and then the pending address calling {acceptGovernance}.
     * @param _position Identifier for the position.
     * @param _newHolder New address for position.
     */
    function setPositionHolder(
        bytes32 _position,
        address _newHolder
    ) external virtual onlyPositionHolder(GOVERNANCE) {
        require(_position != GOVERNANCE, "!two step flow");
        _setPositionHolder(_position, _newHolder);
    }

    /**
     * @notice Sets the default time until profits are fully unlocked for new vaults.
     * @param _newDefaultProfitMaxUnlockTime New value for defaultProfitMaxUnlockTime.
     */
    function setDefaultProfitMaxUnlockTime(
        uint256 _newDefaultProfitMaxUnlockTime
    ) external virtual onlyPositionHolder(GOVERNANCE) {
        defaultProfitMaxUnlockTime = _newDefaultProfitMaxUnlockTime;

        emit UpdateDefaultProfitMaxUnlockTime(_newDefaultProfitMaxUnlockTime);
    }

    /**
     * @notice Accept the Governance role.
     * @dev Caller must be the Pending Governance.
     */
    function acceptGovernance()
        external
        virtual
        onlyPositionHolder(PENDING_GOVERNANCE)
    {
        // Set the Governance role to the caller.
        _setPositionHolder(GOVERNANCE, msg.sender);
        // Reset the Pending Governance.
        _setPositionHolder(PENDING_GOVERNANCE, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the name of this contract.
     */
    function name() external view virtual returns (string memory) {
        return string(abi.encodePacked(projectName, " Role Manager"));
    }

    /**
     * @notice Get all vaults that this role manager controls..
     * @return The full array of vault addresses.
     */
    function getAllVaults() external view virtual returns (address[] memory) {
        return vaults;
    }

    /**
     * @notice Get the vault for a specific asset, api and category.
     * @dev This will return address(0) if one has not been added or deployed.
     *
     * @param _asset The underlying asset used.
     * @param _apiVersion The version of the vault.
     * @param _category The category of the vault.
     * @return The vault for the specified `_asset`, `_apiVersion` and `_category`.
     */
    function getVault(
        address _asset,
        string memory _apiVersion,
        uint256 _category
    ) external view virtual returns (address) {
        return _assetToVault[_asset][_apiVersion][_category];
    }

    /**
     * @notice Get the latest vault for a specific asset.
     * @dev This will default to using category 1.
     * @param _asset The underlying asset used.
     * @return _vault latest vault for the specified `_asset` if any.
     */
    function latestVault(
        address _asset
    ) external view virtual returns (address) {
        return latestVault(_asset, 1);
    }

    /**
     * @notice Get the latest vault for a specific asset.
     * @param _asset The underlying asset used.
     * @param _category The category of the vault.
     * @return _vault latest vault for the specified `_asset` if any.
     */
    function latestVault(
        address _asset,
        uint256 _category
    ) public view virtual returns (address _vault) {
        address releaseRegistry = Registry(getPositionHolder(REGISTRY))
            .releaseRegistry();
        uint256 numReleases = ReleaseRegistry(releaseRegistry).numReleases();

        for (uint256 i = numReleases; i > 0; --i) {
            string memory apiVersion = IVaultFactory(
                ReleaseRegistry(releaseRegistry).factories(i - 1)
            ).apiVersion();

            _vault = _assetToVault[_asset][apiVersion][_category];
            if (_vault != address(0)) {
                break;
            }
        }
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
     * @notice Get the category for a specific vault.
     * @dev Will return 0 if the vault is not managed by this contract.
     * @param _vault Address of the vault.
     * @return . The category of the vault if any.
     */
    function getCategory(
        address _vault
    ) external view virtual returns (uint256) {
        return vaultConfig[_vault].category;
    }

    /**
     * @notice Get the address assigned to the Governance position.
     * @return The address assigned to the Governance position.
     */
    function getGovernance() external view virtual returns (address) {
        return getPositionHolder(GOVERNANCE);
    }

    /**
     * @notice Get the address assigned to the Pending Governance position.
     * @return The address assigned to the Pending Governance position.
     */
    function getPendingGovernance() external view virtual returns (address) {
        return getPositionHolder(PENDING_GOVERNANCE);
    }

    /**
     * @notice Get the address assigned to the Management position.
     * @return The address assigned to the Management position.
     */
    function getManagement() external view virtual returns (address) {
        return getPositionHolder(MANAGEMENT);
    }

    /**
     * @notice Get the address assigned to the Keeper position.
     * @return The address assigned to the Keeper position.
     */
    function getKeeper() external view virtual returns (address) {
        return getPositionHolder(KEEPER);
    }

    /**
     * @notice Get the address assigned to the Registry.
     * @return The address assigned to the Registry.
     */
    function getRegistry() external view virtual returns (address) {
        return getPositionHolder(REGISTRY);
    }

    /**
     * @notice Get the address assigned to the accountant.
     * @return The address assigned to the accountant.
     */
    function getAccountant() external view virtual returns (address) {
        return getPositionHolder(ACCOUNTANT);
    }

    /**
     * @notice Get the address assigned to be the debt allocator if any.
     * @return The address assigned to be the debt allocator if any.
     */
    function getDebtAllocator() external view virtual returns (address) {
        return getPositionHolder(DEBT_ALLOCATOR);
    }

    /**
     * @notice Get the roles given to the Governance position.
     * @return The roles given to the Governance position.
     */
    function getGovernanceRoles() external view virtual returns (uint256) {
        return getPositionRoles(GOVERNANCE);
    }

    /**
     * @notice Get the roles given to the Management position.
     * @return The roles given to the Management position.
     */
    function getManagementRoles() external view virtual returns (uint256) {
        return getPositionRoles(MANAGEMENT);
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
}
