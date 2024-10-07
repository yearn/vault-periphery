// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {RoleManager} from "./RoleManager.sol";
import {Clonable} from "@periphery/utils/Clonable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Registry, RegistryFactory} from "../registry/RegistryFactory.sol";
import {AccountantFactory, Accountant} from "../accountants/AccountantFactory.sol";
import {DebtAllocatorFactory} from "../debtAllocators/DebtAllocatorFactory.sol";
import {IProtocolAddressProvider} from "../interfaces/IProtocolAddressProvider.sol";

/// @title Role Manager Factory
/// @dev Used to either deploy single generic Role Managers or
///     to easily configure and setup a new project that uses the Yearn V3 system.
contract RoleManagerFactory is Clonable {
    event NewRoleManager(address indexed roleManager);

    event NewProject(bytes32 indexed projectId, address indexed roleManager);

    struct Project {
        address roleManager;
        address registry;
        address accountant;
        address debtAllocator;
    }

    bytes32 public constant KEEPER = keccak256("Keeper");
    /// @notice Position ID for the Registry.
    bytes32 public constant REGISTRY_FACTORY = keccak256("Registry Factory");
    /// @notice Position ID for the Accountant.
    bytes32 public constant ACCOUNTANT_FACTORY =
        keccak256("Accountant Factory");
    /// @notice Position ID for Debt Allocator Factory
    bytes32 public constant DEBT_ALLOCATOR_FACTORY =
        keccak256("Debt Allocator Factory");

    string public apiVersion = "v3.0.3";

    address public immutable protocolAddressProvider;

    mapping(bytes32 => Project) public projects;

    constructor(address _addressProvider) {
        protocolAddressProvider = _addressProvider;

        original = address(new RoleManager());
    }

    /**
     * @notice Create a new RoleManager instance
     * @param _projectName The name of the project
     * @param _governance The address of governance
     * @param _management The address of management
     * @param _keeper The address of the keeper
     * @param _registry The address of the projects registry
     * @param _accountant The address of the projects accountant
     * @param _debtAllocator The address of the projects debt allocator
     * @return _roleManager address of the newly created RoleManager
     */
    function newRoleManager(
        string calldata _projectName,
        address _governance,
        address _management,
        address _keeper,
        address _registry,
        address _accountant,
        address _debtAllocator
    ) external virtual returns (address _roleManager) {
        _roleManager = _clone();

        RoleManager(_roleManager).initialize(
            _projectName,
            _governance,
            _management,
            _keeper,
            _registry,
            _accountant,
            _debtAllocator
        );

        emit NewRoleManager(_roleManager);
    }

    /**
     * @notice Create a new project with associated periphery contracts.
        This will deploy and complete full setup with default configuration for
        a new V3 project to exist.
     * @param _name The name of the project
     * @param _governance The address of governance to use
     * @param _management The address of management to use
     * @return _roleManager address of the newly created RoleManager for the project
     */
    function newProject(
        string calldata _name,
        address _governance,
        address _management
    ) external virtual returns (address _roleManager) {
        bytes32 _id = getProjectId(_name, _governance);
        require(projects[_id].roleManager == address(0), "project exists");

        // Deploy new Registry
        address _registry = RegistryFactory(
            _fromAddressProvider(REGISTRY_FACTORY)
        ).createNewRegistry(string(abi.encodePacked(_name, " Registry")));

        address _accountant = AccountantFactory(
            _fromAddressProvider(ACCOUNTANT_FACTORY)
        ).newAccountant(address(this), _governance);

        address _debtAllocator = DebtAllocatorFactory(
            _fromAddressProvider(DEBT_ALLOCATOR_FACTORY)
        ).newDebtAllocator(_management);

        _roleManager = _clone();

        RoleManager(_roleManager).initialize(
            _name,
            _governance,
            _management,
            _fromAddressProvider(KEEPER),
            _registry,
            _accountant,
            _debtAllocator
        );

        // Give Role Manager the needed access in the registry and accountant.
        Registry(_registry).setEndorser(_roleManager, true);
        Registry(_registry).transferGovernance(_governance);

        Accountant(_accountant).setVaultManager(_roleManager);
        Accountant(_accountant).setFutureFeeManager(_governance);

        projects[_id] = Project({
            roleManager: _roleManager,
            registry: _registry,
            accountant: _accountant,
            debtAllocator: _debtAllocator
        });

        emit NewProject(_id, _roleManager);
    }

    /**
     * @notice Generates a unique project ID
     * @param _name The name of the project
     * @param _governance The address of the governance
     * @return The generated project ID
     */
    function getProjectId(
        string memory _name,
        address _governance
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_name, _governance, block.chainid));
    }

    /**
     * @notice Retrieves an address from the protocol address provider
     * @param _id The ID of the address to retrieve
     * @return The retrieved address
     */
    function _fromAddressProvider(bytes32 _id) internal view returns (address) {
        return
            IProtocolAddressProvider(protocolAddressProvider).getAddress(_id);
    }
}
