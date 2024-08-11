// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Positions} from "./Positions.sol";
import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {ReleaseRegistry} from "../registry/ReleaseRegistry.sol";
import {IProtocolAddressProvider} from "../interfaces/IProtocolAddressProvider.sol";

contract V3Deployer is Positions {
    bytes32 public constant KEEPER = keccak256("Keeper");
    /// @notice Position ID for the Registry.
    bytes32 public constant REGISTRY = keccak256("Vault Factory");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT = keccak256("Accountant");
    /// @notice Position ID for Debt Allocator
    bytes32 public constant DEBT_ALLOCATOR = keccak256("Debt Allocator");
    /// @notice Position ID for the Allocator Factory.
    bytes32 public constant ALLOCATOR_FACTORY = keccak256("Allocator Factory");

    string public apiVersion = "v3.0.2";

    address public immutable protocolAddressProvider;

    /// @notice Default time until profits are fully unlocked for new vaults.
    uint256 public defaultProfitMaxUnlock = 7 days;

    constructor(address _addressProvider) {
        protocolAddressProvider = _addressProvider;

        // SEt keeper and debt allocator Roles
    }

    function newVault(
        address _token,
        string calldata _name,
        string calldata _symbol
    ) external returns (address, address) {
        return
            _newVault(
                _token,
                _name,
                _symbol,
                msg.sender,
                address(0),
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _token,
        string calldata _name,
        string calldata _symbol,
        address _roleManager
    ) external returns (address, address) {
        return
            _newVault(
                _token,
                _name,
                _symbol,
                _roleManager,
                address(0),
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _token,
        string calldata _name,
        string calldata _symbol,
        address _roleManager,
        address _accountant
    ) external returns (address, address) {
        return
            _newVault(
                _token,
                _name,
                _symbol,
                _roleManager,
                _accountant,
                defaultProfitMaxUnlock
            );
    }

    function newVault(
        address _token,
        string calldata _name,
        string calldata _symbol,
        address _roleManager,
        address _accountant,
        uint256 _profitMaxUnlockTime
    ) external returns (address, address) {
        return
            _newVault(
                _token,
                _name,
                _symbol,
                _roleManager,
                _accountant,
                _profitMaxUnlockTime
            );
    }

    function _newVault(
        address _token,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        address _accountant,
        address _depositLimit
    ) internal returns (address _vault, address _debtAllocator) {
        _vault = IVaultFactory(getLatestFactory()).deploy_new_vault(
            _token,
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
            ReleaseRegistry(
                IProtocolAddressProvider(protocolAddressProvider)
                    .getReleaseRegistry()
            ).getLatestFactory();
    }

    function getKeeper() public view returns (address) {
        return IProtocolAddressProvider(protocolAddressProvider).getKeeper();
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
        _setRole(_vault, getKeeper(), getPositionRoles(KEEPER));

        // Give the specific debt allocator its roles.
        _setRole(
            _vault,
            _debtAllocator, 
            getPositionRoles(DEBT_ALLOCATOR)
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
    function _setAccountant(address _vault, address _accountant) internal virtual {
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
}
