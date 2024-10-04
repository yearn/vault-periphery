// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, RoleManager, IVault, Roles, MockStrategy, DebtAllocator} from "../utils/Setup.sol";

contract TestRoleManagerFactory is Setup {
    event RoleSet(address indexed account, uint256 role);

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

    /// @notice Emitted when a new address is set for a position.
    event UpdatePositionHolder(
        bytes32 indexed position,
        address indexed newAddress
    );

    /// @notice Emitted when a vault is removed.
    event RemovedVault(address indexed vault);

    /// @notice Emitted when a new set of roles is set for a position
    event UpdatePositionRoles(bytes32 indexed position, uint256 newRoles);

    /// @notice Emitted when the defaultProfitMaxUnlock variable is updated.
    event UpdateDefaultProfitMaxUnlock(uint256 newDefaultProfitMaxUnlock);

    IVault public vault;
    MockStrategy public strategy;

    uint256 constant daddy_roles = Roles.ALL;
    uint256 constant brain_roles =
        Roles.REPORTING_MANAGER |
            Roles.DEBT_MANAGER |
            Roles.QUEUE_MANAGER |
            Roles.DEPOSIT_LIMIT_MANAGER |
            Roles.DEBT_PURCHASER |
            Roles.PROFIT_UNLOCK_MANAGER;
    uint256 constant keeper_roles = Roles.REPORTING_MANAGER;
    uint256 constant debt_allocator_roles =
        Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER;

    function setUp() public override {
        super.setUp();
        vault = createVault(
            address(asset),
            daddy,
            MAX_INT,
            WEEK,
            "Test Vault",
            "tvTEST"
        );
        strategy = createStrategy(address(asset));

        vm.prank(daddy);
        releaseRegistry.newRelease(address(vaultFactory));
    }
}
