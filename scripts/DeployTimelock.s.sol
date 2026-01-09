// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockExecutor} from "../src/managers/TimelockExecutor.sol";
import {YearnRoleManager} from "../src/managers/YearnRoleManager.sol";
import {TimelockConfig} from "./TimelockConfig.sol";

/// @title Multichain Timelock Deployment Script
/// @notice Deploys TimelockController, TimelockExecutor, and optionally YearnRoleManager
/// @dev Uses CREATE3 for deterministic cross-chain addresses
contract DeployTimelock is Script {
    // CreateX factory address (same on all chains)
    ICreateX public constant CREATE_X =
        ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Salt bases for deterministic addresses
    bytes32 public constant TIMELOCK_SALT =
        keccak256("yearn.timelock.controller.v1");
    bytes32 public constant EXECUTOR_SALT =
        keccak256("yearn.timelock.executor.v1");

    // Deployer address - SET THIS before running the script
    address public constant DEPLOYER =
        0x78d4BDEBc0B4140f01BAB63085F94A5a7A1294f2;

    // Deployed addresses
    address public timelockController;
    address public timelockExecutor;
    address public roleManager;

    function run() external {
        require(DEPLOYER != address(0), "Set DEPLOYER address in script");

        vm.startBroadcast();

        // Get chain-specific configuration
        TimelockConfig.ChainConfig memory config = TimelockConfig.getConfig();

        // Precompute addresses using the guarded salt
        // For CREATE3, pass the guarded salt and CreateX address
        bytes32 executorSalt = _generateSalt(EXECUTOR_SALT);
        address predictedExecutor = computeCreate3Address(executorSalt);
        bytes32 timelockControllerSalt = _generateSalt(TIMELOCK_SALT);
        address predictedTimelockController = computeCreate3Address(
            timelockControllerSalt
        );

        console.log("Deployer address:", DEPLOYER);
        console.log("Predicted TimelockExecutor address:", predictedExecutor);
        console.log(
            "Predicted TimelockController address:",
            predictedTimelockController
        );

        // Step 1: Deploy TimelockController via CREATE3
        // Daddy is the proposer, executor contract + daddy are executors
        timelockController = _deployTimelockController(
            config,
            predictedExecutor
        );
        require(
            timelockController == predictedTimelockController,
            "TimelockController address mismatch"
        );
        console.log("TimelockController deployed at:", timelockController);

        // Step 2: Deploy TimelockExecutor via CREATE3
        // Governance is the timelock itself, timelock reference is the deployed controller
        timelockExecutor = _deployTimelockExecutor(
            timelockController,
            config.brain
        );
        // Verify the executor was deployed to the predicted address
        require(
            timelockExecutor == predictedExecutor,
            "Executor address mismatch"
        );
        console.log("TimelockExecutor deployed at:", timelockExecutor);

        // Step 3: Deploy YearnRoleManager if not already deployed
        if (config.existingRoleManager == address(0)) {
            roleManager = _deployRoleManager(config, timelockController);
            console.log("YearnRoleManager deployed at:", roleManager);
        } else {
            roleManager = config.existingRoleManager;
            console.log("Using existing YearnRoleManager at:", roleManager);
        }

        vm.stopBroadcast();

        // Log summary
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("TimelockController:", timelockController);
        console.log("TimelockExecutor:", timelockExecutor);
        console.log("YearnRoleManager:", roleManager);
    }

    /// @notice Deploy TimelockController using CREATE3
    /// @param config Chain-specific configuration
    /// @param _executor Precomputed address of the TimelockExecutor contract
    /// @return The deployed TimelockController address
    function _deployTimelockController(
        TimelockConfig.ChainConfig memory config,
        address _executor
    ) internal returns (address) {
        // Proposers array - daddy is the only proposer
        address[] memory proposers = new address[](1);
        proposers[0] = config.daddy;

        // Executors array - executor contract and daddy can execute
        address[] memory executors = new address[](2);
        executors[0] = _executor;
        executors[1] = config.daddy;

        // Admin - set to address(0) to disable optional admin
        // The timelock is self-administered
        address admin = address(0);

        // Encode constructor arguments
        bytes memory initCode = abi.encodePacked(
            type(TimelockController).creationCode,
            abi.encode(config.minDelay, proposers, executors, admin)
        );

        // Generate salt with deployer prefix for frontrun protection
        bytes32 salt = _generateSalt(TIMELOCK_SALT);

        // Deploy via CREATE3
        return CREATE_X.deployCreate3(salt, initCode);
    }

    /// @notice Deploy TimelockExecutor using CREATE3
    /// @param _timelock Address of the deployed TimelockController
    /// @return The deployed TimelockExecutor address
    function _deployTimelockExecutor(
        address _timelock,
        address _brain
    ) internal returns (address) {
        // Encode constructor arguments
        bytes memory initCode = abi.encodePacked(
            type(TimelockExecutor).creationCode,
            abi.encode(_brain, _timelock)
        );

        // Generate salt with deployer prefix for frontrun protection
        bytes32 salt = _generateSalt(EXECUTOR_SALT);

        // Deploy via CREATE3
        return CREATE_X.deployCreate3(salt, initCode);
    }

    /// @notice Deploy YearnRoleManager using normal CREATE
    /// @param config Chain-specific configuration
    /// @param _timelock Address of the TimelockController (used as governance and strategy manager)
    /// @return The deployed YearnRoleManager address
    function _deployRoleManager(
        TimelockConfig.ChainConfig memory config,
        address _timelock
    ) internal returns (address) {
        // Deploy via normal CREATE
        // Constructor args:
        // - governance: timelock
        // - daddy: from config
        // - brain: from config
        // - security: from config
        // - keeper: from config
        // - strategyManager: timelock
        // - registry: constant address
        return
            address(
                new YearnRoleManager(
                    _timelock, // governance
                    config.daddy, // daddy
                    config.brain, // brain
                    config.security, // security
                    config.keeper, // keeper
                    _timelock, // strategyManager
                    TimelockConfig.REGISTRY // registry
                )
            );
    }

    /// @notice Generate a salt with deployer address prefix for frontrun protection
    /// @param baseSalt The base salt value
    /// @return The salt with deployer prefix
    function _generateSalt(bytes32 baseSalt) internal pure returns (bytes32) {
        // Bytes 0-19: deployer address (permissioned deploy protection)
        // Byte 20 (21st byte): 0x00 (no cross-chain redeploy protection)
        // Bytes 21-31: unique identifier from baseSalt
        return bytes32(uint256(uint160(DEPLOYER)) << 96) | (baseSalt >> 168);
    }

    function _efficientHash(
        bytes32 a,
        bytes32 b
    ) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }

    /// @notice Compute the CREATE3 address for a given salt and deployer (for verification)
    /// @param salt The salt to compute the address for
    /// @return The predicted deployment address
    function computeCreate3Address(bytes32 salt) public view returns (address) {
        bytes32 guardedSalt = _efficientHash({
            a: bytes32(uint256(uint160(DEPLOYER))),
            b: salt
        });
        return CREATE_X.computeCreate3Address(guardedSalt);
    }
}

/// @notice Interface for CreateX factory
interface ICreateX {
    /// @notice Deploys a new contract using CREATE3
    /// @param salt The 32-byte random value used to create the proxy contract address
    /// @param initCode The creation bytecode
    /// @return newContract The deployed contract address
    function deployCreate3(
        bytes32 salt,
        bytes memory initCode
    ) external payable returns (address newContract);

    /// @notice Computes the CREATE3 address for a given salt and deployer
    /// @param salt The salt value
    /// @return predicted The predicted deployment address
    function computeCreate3Address(
        bytes32 salt
    ) external view returns (address predicted);
}
