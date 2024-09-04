// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Positions} from "./Positions.sol";
import {RoleManager} from "./RoleManager.sol";
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
        address roleManager;
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

    function getLatestFactory() public view returns (address) {
        return
            ReleaseRegistry(_fromAddressProvider(RELEASE_REGISTRY))
                .latestFactory();
    }

    function _fromAddressProvider(bytes32 _id) internal view returns (address) {
        return
            IProtocolAddressProvider(protocolAddressProvider).getAddress(_id);
    }

    function newProject(address _governance) external virtual {
        bytes32 _id = getProjectId(_governance);
        require(projects[_id].roleManager == address(0), "project exists");

        // Deploy new Registry
        address _registry = RegistryFactory(
            _fromAddressProvider(REGISTRY_FACTORY)
        ).createNewRegistry(
                string(abi.encodePacked(_prefix, " Vault Registry"))
            );

        address _accountant = AccountantFactory(
            _fromAddressProvider(ACCOUNTANT_FACTORY)
        ).newAccountant(_roleManager, _roleManager);

        address _debtAllocator = DebtAllocatorFactory(
            _fromAddressProvider(ALLOCATOR_FACTORY)
        ).newDebtAllocator(_roleManager);

        address _roleManager = address(
            new RoleManager(
                _governance,
                _governance,
                _fromAddressProvider(KEEPER),
                _registry,
                _accountant,
                _debtAllocator
            )
        );

        projects[_id] = Project({
            roleManager: _roleManager,
            registry: _registry,
            accountant: _accountant,
            debtAllocator: _debtAllocator
        });

        // Event
    }

    function getProjectId(
        address _governance
    ) public view virtual returns (bytes32) {
        return
            keccak256(abi.encodePacked(_governance, chain.id, block.timestamp));
    }
}
