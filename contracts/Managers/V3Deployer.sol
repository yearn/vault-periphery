// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Positions} from "./Positions.sol";
import {Registry, RegistryFactory} from "../registry/RegistryFactory.sol";
import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {ReleaseRegistry} from "../registry/ReleaseRegistry.sol";
import {AccountantFactory} from "../accountants/AccountantFactory.sol";
import {DebtAllocatorFactory} from "../debtAllocators/DebtAllocatorFactory.sol";
import {IProtocolAddressProvider} from "../interfaces/IProtocolAddressProvider.sol";

// TODO:
// 1. Initiate new "project"
// 2. Can deploy using project id

contract V3Deployer is Positions {
    struct Project {
        string prefix;
        address registry;
        address roleManager;
        address accountant;
        address debtAllocator;
    }

    bytes32 public constant KEEPER = keccak256("Keeper");
    /// @notice Position ID for the Registry.
    bytes32 public constant RELEASE_REGISTRY = keccak256("Release Registry");
    /// @notice Position ID for the Registry.
    bytes32 public constant REGISTRY_FACTORY = keccak256("Registry Factory");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT = keccak256("Accountant");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT_FACTORY =
        keccak256("Accountant Factory");
    /// @notice Position ID for Debt Allocator
    bytes32 public constant DEBT_ALLOCATOR = keccak256("Debt Allocator");
    /// @notice Position ID for the Allocator Factory.
    bytes32 public constant ALLOCATOR_FACTORY = keccak256("Allocator Factory");

    string public apiVersion = "v3.0.2";

    address public immutable protocolAddressProvider;

    /// @notice Default time until profits are fully unlocked for new vaults.
    uint256 public defaultProfitMaxUnlock = 7 days;

    mapping(bytes32 => Project) public projects;

    constructor(address _addressProvider) {
        protocolAddressProvider = _addressProvider;

        // SEt keeper and debt allocator Roles
    }

    function newVault(
        address _asset,
        bytes32 _projectId
    ) external returns (address, address) {
        string memory _prefix = projects[_projectId].prefix;
        string memory assetSymbol = ERC20(_asset).symbol();

        // Name is "{SYMBOL} {PREFIX}Vault" ex: PREFIX=yv, USDC yvVault
        string memory _name = string(
            abi.encodePacked(assetSymbol, " ", _prefix, "Vault")
        );
        // Symbol is "{PREFIX}{SYMBOL}". ex: PREFIX=yv, yvUSDC
        string memory _symbol = string(abi.encodePacked(_prefix, assetSymbol));

        return newVault(_asset, _projectId, _name, _symbol);
    }

    function newVault(
        address _asset,
        bytes32 _projectId,
        string memory _name,
        string memory _symbol
    ) public returns (address _vault, address _allocator) {
        Project memory project = projects[_projectId];
        require(project.roleManager != address(0), "invalid ID");

        (_vault, _allocator) = _newVault(
            _asset,
            _name,
            _symbol,
            project.roleManager,
            project.accountant,
            2 ** 256 - 1,
            defaultProfitMaxUnlock
        );

        Registry(project.registry).endorseVault(_vault, 0, 1, block.timestamp);
    }

    function newVault(
        address _asset,
        string calldata _name,
        string calldata _symbol
    ) external returns (address, address) {
        return
            _newVault(
                _asset,
                _name,
                _symbol,
                msg.sender,
                address(0),
                0,
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _asset,
        string calldata _name,
        string calldata _symbol,
        address _roleManager
    ) external returns (address, address) {
        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                address(0),
                0,
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _asset,
        string calldata _name,
        string calldata _symbol,
        address _roleManager,
        address _accountant
    ) external returns (address, address) {
        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _accountant,
                0,
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _asset,
        string calldata _name,
        string calldata _symbol,
        address _roleManager,
        address _accountant,
        uint256 _depositLimit
    ) external returns (address, address) {
        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _accountant,
                _depositLimit,
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _asset,
        string calldata _name,
        string calldata _symbol,
        address _roleManager,
        address _accountant,
        uint256 _depositLimit,
        uint256 _profitMaxUnlockTime
    ) external returns (address, address) {
        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _accountant,
                _depositLimit,
                _profitMaxUnlockTime
            );
    }

    function _newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        address _accountant,
        uint256 _depositLimit,
        uint256 _profitMaxUnlockTime
    ) internal returns (address _vault, address _debtAllocator) {
        _vault = IVaultFactory(getLatestFactory()).deploy_new_vault(
            _asset,
            _name,
            _symbol,
            address(this),
            _profitMaxUnlockTime
        );

        // Debt Allocator
        _debtAllocator = _deployAllocator(_vault);

        // Accountant
        _setAccountant(_vault, _accountant);

        // Deposit Limit
        _setDepositLimit(_vault, _depositLimit);

        IVault(_vault).transfer_role_manager(_roleManager);
    }

    function getLatestFactory() public view returns (address) {
        return
            ReleaseRegistry(_fromAddressProvider(RELEASE_REGISTRY))
                .latestFactory();
    }

    function _fromAddressProvider(bytes32 _id) internal view returns (address) {
        return
            IProtocolAddressProvider(protocolAddressProvider).getAddress(_id);
    }

    function _deployAllocator(
        address _vault
    ) internal virtual returns (address _debtAllocator) {
        address factory = getPositionHolder(ALLOCATOR_FACTORY);
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
        // Set the roles for the Keeper.
        _setRole(
            _vault,
            _fromAddressProvider(KEEPER),
            getPositionRoles(KEEPER)
        );

        // Give the specific debt allocator its roles.
        _setRole(_vault, _debtAllocator, getPositionRoles(DEBT_ALLOCATOR));
    }

    /**
     * @dev Used internally to set the roles on a vault for a given position.
     *   Will not set the roles if the position holder is address(0).
     *   This does not check that the roles are !=0 because it is expected that
     *   the holder will be set to 0 if the position is not being used.
     *
     */
    function _setRole(
        address _vault,
        address _holder,
        uint256 _roles
    ) internal virtual {
        if (_holder != address(0)) {
            IVault(_vault).set_role(_holder, _roles);
        }
    }

    /**
     * @dev Sets the accountant on the vault and adds the vault to the accountant.
     *   This temporarily gives the `ACCOUNTANT_MANAGER` role to this contract.
     * @param _vault Address of the vault to set up the accountant for.
     */
    function _setAccountant(
        address _vault,
        address _accountant
    ) internal virtual {
        // If there is an accountant set.
        if (_accountant != address(0)) {
            // Temporarily give this contract the ability to set the accountant.
            IVault(_vault).add_role(address(this), Roles.ACCOUNTANT_MANAGER);

            // Set the account on the vault.
            IVault(_vault).set_accountant(_accountant);

            // Take away the role.
            IVault(_vault).remove_role(address(this), Roles.ACCOUNTANT_MANAGER);
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

    function registerNewProject(
        string memory _prefix,
        address _registry,
        address _roleManager,
        address _accountant,
        address _debtAllocator
    ) external virtual {
        bytes32 _id = getProjectId(_prefix);
        require(projects[_id].roleManager == address(0), "project exists");

        // Default to msg sender if none given
        if (_roleManager == address(0)) _roleManager = msg.sender;

        // Deploy new Registry
        if (_registry == address(0)) {
            _registry = RegistryFactory(_fromAddressProvider(REGISTRY_FACTORY))
                .createNewRegistry(
                    string(abi.encodePacked(_prefix, " Vault Registry"))
                );
        }

        if (_accountant == address(0)) {
            _accountant = AccountantFactory(
                _fromAddressProvider(ACCOUNTANT_FACTORY)
            ).newAccountant(_roleManager, _roleManager);
        }

        if (_debtAllocator == address(0)) {
            _debtAllocator = DebtAllocatorFactory(
                _fromAddressProvider(ALLOCATOR_FACTORY)
            ).newDebtAllocator(_roleManager);
        }

        projects[_id] = Project({
            prefix: _prefix,
            roleManager: _roleManager,
            registry: _registry,
            accountant: _accountant,
            debtAllocator: _debtAllocator
        });

        // Event
    }

    function getProjectId(
        string memory _prefix
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_prefix));
    }
}
