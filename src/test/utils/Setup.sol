// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ExtendedTest} from "./ExtendedTest.sol";
import {VyperDeployer} from "./VyperDeployer.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockStrategy} from "../../mocks/MockStrategy.sol";
import {MockTokenized} from "../../mocks/MockTokenizedStrategy.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

import {ReleaseRegistry} from "../../registry/ReleaseRegistry.sol";
import {RegistryFactory} from "../../registry/RegistryFactory.sol";
import {Registry} from "../../registry/Registry.sol";

import {AccountantFactory} from "../../accountants/AccountantFactory.sol";
import {Accountant} from "../../accountants/Accountant.sol";

import {IProtocolAddressProvider} from "../../interfaces/IProtocolAddressProvider.sol";

import {GenericDebtAllocatorFactory} from "../../debtAllocators/Generic/GenericDebtAllocatorFactory.sol";
import {GenericDebtAllocator} from "../../debtAllocators/Generic/GenericDebtAllocator.sol";
import {DebtAllocatorFactory} from "../../debtAllocators/DebtAllocatorFactory.sol";
import {DebtAllocator} from "../../debtAllocators/DebtAllocator.sol";
import {DebtOptimizerApplicator} from "../../debtAllocators/DebtOptimizerApplicator.sol";

import {RoleManager} from "../../managers/RoleManager.sol";
import {RoleManagerFactory} from "../../managers/RoleManagerFactory.sol";

import {Keeper} from "../../Keeper.sol";

import {ISplitterFactory} from "../../interfaces/ISplitterFactory.sol";
import {ISplitter} from "../../interfaces/ISplitter.sol";

contract Setup is ExtendedTest {
    // Constants
    uint256 constant MAX_BPS = 10_000;
    uint256 constant MAX_INT = type(uint256).max;
    uint256 constant WEEK = 7 days;
    address constant ZERO_ADDRESS = address(0);

    uint256 public minFuzzAmount = 10_000;
    uint256 public maxFuzzAmount = 100e18;

    // Accounts
    address public daddy;
    address public brain;
    address public security;
    address public management;
    address public feeRecipient;
    address public user;
    address public vaultManager;
    address public strategyManager;

    // Contracts
    MockERC20 public asset;

    VyperDeployer public vyperDeployer;

    IVaultFactory public vaultFactory;

    Registry public registry;
    ReleaseRegistry public releaseRegistry;
    RegistryFactory public registryFactory;

    Accountant public accountant;
    AccountantFactory public accountantFactory;

    IProtocolAddressProvider public addressProvider;

    DebtAllocator public debtAllocator;
    DebtAllocatorFactory public debtAllocatorFactory;
    DebtOptimizerApplicator public debtOptimizerApplicator;

    RoleManager public roleManager;
    RoleManagerFactory public roleManagerFactory;

    Keeper public keeper;

    ISplitter public splitter;
    ISplitterFactory public splitterFactory;

    GenericDebtAllocator public genericAllocator;
    GenericDebtAllocatorFactory public genericAllocatorFactory;

    // Setup function
    function setUp() public virtual {
        // Setup accounts
        daddy = address(this);
        brain = address(0x1);
        security = address(0x2);
        management = address(0x3);
        feeRecipient = address(0x4);
        user = address(0x6);
        vaultManager = address(0x7);
        strategyManager = address(0x8);

        vm.label(daddy, "daddy");
        vm.label(brain, "brain");
        vm.label(security, "security");
        vm.label(management, "management");
        vm.label(feeRecipient, "feeRecipient");
        vm.label(user, "user");
        vm.label(vaultManager, "vaultManager");
        vm.label(strategyManager, "strategyManager");

        // Deploy contracts
        vyperDeployer = new VyperDeployer();
        asset = new MockERC20();
        vaultFactory = setupFactory();

        addressProvider = IProtocolAddressProvider(deployAddressProvider());

        releaseRegistry = new ReleaseRegistry(daddy);
        registryFactory = new RegistryFactory(address(releaseRegistry));
        registry = Registry(
            registryFactory.createNewRegistry("New test Registry", daddy)
        );

        accountantFactory = new AccountantFactory();
        accountant = Accountant(
            accountantFactory.newAccountant(
                daddy,
                feeRecipient,
                100,
                1000,
                0,
                0,
                10000,
                0
            )
        );

        debtAllocatorFactory = new DebtAllocatorFactory();
        debtAllocator = DebtAllocator(
            debtAllocatorFactory.newDebtAllocator(brain)
        );
        debtOptimizerApplicator = new DebtOptimizerApplicator(
            address(debtAllocator)
        );

        keeper = new Keeper();

        roleManagerFactory = new RoleManagerFactory(address(addressProvider));
        roleManager = RoleManager(
            roleManagerFactory.newRoleManager(
                "Test",
                daddy,
                brain,
                address(keeper),
                address(registry),
                address(accountant),
                address(debtAllocator)
            )
        );

        vm.startPrank(daddy);
        accountant.setVaultManager(address(roleManager));

        registry.setEndorser(address(roleManager), true);
        vm.stopPrank();

        genericAllocatorFactory = new GenericDebtAllocatorFactory();
    }

    function setupFactory() public returns (IVaultFactory _factory) {
        address original = vyperDeployer.deployContract(
            "lib/yearn-vaults-v3/contracts/",
            "VaultV3"
        );

        bytes memory args = abi.encode("Test vault Factory", original, daddy);

        _factory = IVaultFactory(
            vyperDeployer.deployContract(
                "lib/yearn-vaults-v3/contracts/",
                "VaultFactory",
                args
            )
        );
    }

    function deployAddressProvider()
        public
        returns (IProtocolAddressProvider _addressProvider)
    {
        bytes memory args = abi.encode(daddy);

        _addressProvider = IProtocolAddressProvider(
            vyperDeployer.deployContract(
                "src/addressProviders/",
                "ProtocolAddressProvider",
                args
            )
        );
    }

    function setupSplitter()
        public
        returns (ISplitterFactory _splitterFactory, ISplitter _splitter)
    {
        _splitter = ISplitter(
            vyperDeployer.deployContract("src/splitter/", "Splitter")
        );

        bytes memory args = abi.encode(address(_splitter));

        _splitterFactory = ISplitterFactory(
            vyperDeployer.deployContract(
                "src/splitter/",
                "SplitterFactory",
                args
            )
        );

        _splitter.initialize("Test Splitter", daddy, management, brain, 5000);
    }

    // Helper functions
    function createToken(
        address _initialUser,
        uint256 _initialAmount
    ) public returns (MockERC20) {
        MockERC20 token = new MockERC20();
        token.mint(_initialUser, _initialAmount);
        return token;
    }

    function createVault(
        address _asset,
        address _governance,
        uint256 _depositLimit,
        uint256 _maxProfitLockingTime,
        string memory _vaultName,
        string memory _vaultSymbol
    ) public returns (IVault) {
        if (bytes(_vaultName).length == 0) {
            _vaultName = string(
                abi.encodePacked("Vault V3 ", uint256(block.timestamp) % 10000)
            );
        }
        IVault vault = IVault(
            vaultFactory.deploy_new_vault(
                _asset,
                _vaultName,
                _vaultSymbol,
                _governance,
                _maxProfitLockingTime
            )
        );

        vm.prank(_governance);
        vault.set_role(daddy, Roles.ALL);

        vm.prank(daddy);
        vault.set_deposit_limit(_depositLimit);

        return vault;
    }

    function createStrategy(address _asset) public returns (MockStrategy) {
        return new MockStrategy(_asset, "3.0.3");
    }

    function deployMockTokenized(
        string memory _name,
        uint256 _apr
    ) public returns (MockTokenized) {
        return
            new MockTokenized(
                address(vaultFactory),
                address(asset),
                _name,
                management,
                address(keeper),
                _apr
            );
    }

    function createVaultAndStrategy(
        address _account,
        uint256 _amountIntoVault
    ) public returns (IVault, MockStrategy) {
        IVault vault = createVault(
            address(asset),
            daddy,
            MAX_INT,
            WEEK,
            "",
            "VV3"
        );
        MockStrategy strategy = createStrategy(address(asset));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        depositIntoVault(vault, user, _amountIntoVault);

        return (vault, strategy);
    }

    function depositIntoVault(
        IVault _vault,
        address _user,
        uint256 _amountToDeposit
    ) public {
        deal(_vault.asset(), _user, _amountToDeposit);

        vm.prank(_user);
        asset.approve(address(_vault), _amountToDeposit);

        vm.prank(_user);
        _vault.deposit(_amountToDeposit, _user);
    }

    function provideStrategyWithDebt(
        IVault _vault,
        address _strategy,
        uint256 _targetDebt
    ) public {
        vm.prank(daddy);
        _vault.update_debt(_strategy, _targetDebt);
    }
}
