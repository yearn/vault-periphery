// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {RoleManager} from "./RoleManager.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Registry, RegistryFactory} from "../registry/RegistryFactory.sol";
import {AccountantFactory, Accountant} from "../accountants/AccountantFactory.sol";
import {DebtAllocatorFactory} from "../debtAllocators/DebtAllocatorFactory.sol";
import {IProtocolAddressProvider} from "../interfaces/IProtocolAddressProvider.sol";

// TODO:
// 1. Initiate new "project"
// 2. Can deploy using project id

contract V3Deployer {
    event NewProject(bytes32 indexed projectId, address indexed roleManager);

    struct Project {
        address roleManager;
        address registry;
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

    mapping(bytes32 => Project) public projects;

    constructor(address _addressProvider) {
        protocolAddressProvider = _addressProvider;
    }

    function _fromAddressProvider(bytes32 _id) internal view returns (address) {
        return
            IProtocolAddressProvider(protocolAddressProvider).getAddress(_id);
    }

    function newProject(
        address _governance,
        address _management
    ) external virtual returns (address _roleManager) {
        bytes32 _id = getProjectId(_governance);
        require(projects[_id].roleManager == address(0), "project exists");

        // Deploy new Registry
        address _registry = RegistryFactory(
            _fromAddressProvider(REGISTRY_FACTORY)
        ).createNewRegistry(string(abi.encodePacked(" Vault Registry")));

        address _accountant = AccountantFactory(
            _fromAddressProvider(ACCOUNTANT_FACTORY)
        ).newAccountant(address(this), _roleManager);

        address _debtAllocator = DebtAllocatorFactory(
            _fromAddressProvider(ALLOCATOR_FACTORY)
        ).newDebtAllocator(_management);

        _roleManager = address(
            new RoleManager(
                _governance,
                _management,
                _fromAddressProvider(KEEPER),
                _registry,
                _accountant,
                _debtAllocator
            )
        );

        Registry(_registry).setEndorser(_roleManager, true);
        Registry(_registry).transferGovernance(_governance);

        Accountant(_accountant).setVaultManager(_roleManager);
        Accountant(_accountant).setFutureFeeManager(_roleManager);

        projects[_id] = Project({
            roleManager: _roleManager,
            registry: _registry,
            accountant: _accountant,
            debtAllocator: _debtAllocator
        });

        // Event
        emit NewProject(_id, _roleManager);
    }

    function getProjectId(
        address _governance
    ) public view virtual returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_governance, block.chainid, block.timestamp)
            );
    }
}
