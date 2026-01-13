// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockExecutor} from "../src/managers/TimelockExecutor.sol";
import {YearnRoleManager} from "../src/managers/YearnRoleManager.sol";

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

/// @title Timelock Deployment Configuration
/// @notice Chain-specific configuration for timelock deployment
library TimelockConfig {
    struct ChainConfig {
        // TimelockController settings
        uint256 minDelay;
        // YearnRoleManager position holders
        address daddy;
        address brain;
        address security;
        address keeper;
        // Existing role manager (address(0) if needs deployment)
        address existingRoleManager;
    }

    /// @notice Registry address - same on all chains
    address public constant REGISTRY =
        0xd40ecF29e001c76Dcc4cC0D9cd50520CE845B038;

    /// @notice Get configuration for the current chain
    function getConfig() internal view returns (ChainConfig memory config) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            // Ethereum Mainnet
            config = ChainConfig({
                minDelay: 1 days,
                daddy: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52,
                brain: 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7,
                security: 0xe5e2Baf96198c56380dDD5E992D7d1ADa0e989c0,
                keeper: 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E,
                existingRoleManager: 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41 // Set to address if already deployed
            });
        } else if (chainId == 137) {
            // Polygon
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xC4ad0000E223E398DC329235e6C497Db5470B626), // TODO: Set Polygon addresses
                brain: address(0x16388000546eDed4D476bd2A4A374B5a16125Bc1),
                security: address(0),
                keeper: address(0x3A95F75f0Ea2FD60b31E7c6180C7B5fC9865492F),
                existingRoleManager: address(0)
            });
        } else if (chainId == 42161) {
            // Arbitrum One
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xb6bc033D34733329971B938fEf32faD7e98E56aD), // TODO: Set Arbitrum addresses
                brain: address(0x6346282DB8323A54E840c6C772B4399C9c655C0d),
                security: address(0xfd99a19Fcf577Be92fDAB4ef162c1644BB056885),
                keeper: address(0xE0D19f6b240659da8E87ABbB73446E7B4346Baee),
                existingRoleManager: address(
                    0x3BF72024420bdc4D7cA6a8b6211829476D6685b1
                )
            });
        } else if (chainId == 10) {
            // Optimism
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xF5d9D6133b698cE29567a90Ab35CfB874204B3A7), // TODO: Set Optimism addresses
                brain: address(0xea3a15df68fCdBE44Fdb0DB675B2b3A14a148b26),
                security: address(0),
                keeper: address(0x21BB199ab3be9E65B1E60b51ea9b0FE9a96a480a),
                existingRoleManager: address(0)
            });
        } else if (chainId == 8453) {
            // Base
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xbfAABa9F56A39B814281D68d2Ad949e88D06b02E), // TODO: Set Base addresses
                brain: address(0x01fE3347316b2223961B20689C65eaeA71348e93),
                security: address(0xFEaE2F855250c36A77b8C68dB07C4dD9711fE36F),
                keeper: address(0x46679Ba8ce6473a9E0867c52b5A50ff97579740E),
                existingRoleManager: address(
                    0xea3481244024E2321cc13AcAa80df1050f1fD456
                )
            });
        } else if (chainId == 100) {
            // Gnosis Chain
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0), // TODO: Set Gnosis addresses
                brain: address(0xFB4464a18d18f3FF439680BBbCE659dB2806A187),
                security: address(0),
                keeper: address(0),
                existingRoleManager: address(0)
            });
        } else if (chainId == 747474) {
            // Katana
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xe6ad5A88f5da0F276C903d9Ac2647A937c917162), // TODO: Set Katana addresses
                brain: address(0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6),
                security: address(0x518C21DC88D9780c0A1Be566433c571461A70149),
                keeper: address(0xC29cbdcf5843f8550530cc5d627e1dd3007EF231),
                existingRoleManager: address(0)
            });
        } else {
            revert("TimelockConfig: unsupported chain");
        }
    }

    /// @notice Check if the chain is supported
    function isSupported() internal view returns (bool) {
        uint256 chainId = block.chainid;
        return
            chainId == 1 ||
            chainId == 137 ||
            chainId == 42161 ||
            chainId == 10 ||
            chainId == 8453 ||
            chainId == 100 ||
            chainId == 747474;
    }
}
