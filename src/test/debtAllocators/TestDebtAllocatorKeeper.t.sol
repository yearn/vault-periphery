// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, DebtAllocator, IVault, Roles, MockStrategy} from "../utils/Setup.sol";
import {DebtAllocatorKeeper} from "../../debtAllocators/DebtAllocatorKeeper.sol";

contract TestDebtAllocatorKeeper is Setup {
    IVault public vault;
    MockStrategy public strategy;
    DebtAllocatorKeeper public debtAllocatorKeeper;

    function setUp() public override {
        super.setUp();

        vault = createVault(address(asset), daddy, MAX_INT, WEEK, "Test Vault", "tvTEST");
        strategy = createStrategy(address(asset));

        debtAllocatorKeeper = new DebtAllocatorKeeper(address(debtAllocator), brain);
    }

    function test_setup() public view {
        assertEq(debtAllocatorKeeper.governance(), brain);
        assertEq(address(debtAllocatorKeeper.DEBT_ALLOCATOR()), address(debtAllocator));
        assertFalse(debtAllocatorKeeper.keepers(user));
        assertFalse(debtAllocatorKeeper.allowedVaults(address(vault)));
    }

    function test_set_keeper() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocatorKeeper.setKeeper(user, true);

        vm.prank(brain);
        vm.expectRevert("ZERO ADDRESS");
        debtAllocatorKeeper.setKeeper(address(0), true);

        vm.prank(brain);
        debtAllocatorKeeper.setKeeper(user, true);
        assertTrue(debtAllocatorKeeper.keepers(user));

        vm.prank(brain);
        debtAllocatorKeeper.setKeeper(user, false);
        assertFalse(debtAllocatorKeeper.keepers(user));
    }

    function test_set_allowed_vault() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocatorKeeper.setAllowedVault(address(vault), true);

        vm.prank(brain);
        vm.expectRevert("ZERO ADDRESS");
        debtAllocatorKeeper.setAllowedVault(address(0), true);

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);
        assertTrue(debtAllocatorKeeper.allowedVaults(address(vault)));

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), false);
        assertFalse(debtAllocatorKeeper.allowedVaults(address(vault)));
    }

    function test_update_debt() public {
        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        vm.prank(user);
        vm.expectRevert("!keeper");
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), amount);

        vm.prank(brain);
        debtAllocatorKeeper.setKeeper(user, true);

        vm.prank(user);
        vm.expectRevert("!allowed");
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), amount);

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);

        vm.prank(user);
        vm.expectRevert("!keeper");
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), amount);

        vm.prank(brain);
        debtAllocator.setKeeper(address(debtAllocatorKeeper), true);

        vm.prank(daddy);
        vault.add_role(address(debtAllocator), Roles.DEBT_MANAGER | Roles.REPORTING_MANAGER);

        vm.prank(user);
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), amount);

        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), amount);

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), false);

        vm.prank(user);
        vm.expectRevert("!allowed");
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), 0);
    }

    function test_allowed_vault_is_not_strategy_specific() public {
        MockStrategy secondStrategy = createStrategy(address(asset));
        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        vm.startPrank(daddy);
        vault.add_strategy(address(strategy));
        vault.add_strategy(address(secondStrategy));
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);
        vault.update_max_debt_for_strategy(address(secondStrategy), MAX_INT);
        vault.add_role(address(debtAllocator), Roles.DEBT_MANAGER);
        vm.stopPrank();

        vm.startPrank(brain);
        debtAllocator.setKeeper(address(debtAllocatorKeeper), true);
        debtAllocatorKeeper.setKeeper(user, true);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);
        vm.stopPrank();

        vm.prank(user);
        debtAllocatorKeeper.update_debt(address(vault), address(strategy), amount / 2);

        vm.prank(user);
        debtAllocatorKeeper.update_debt(address(vault), address(secondStrategy), amount / 2);

        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), amount);
    }

    function test_set_strategy_debt_ratio() public {
        uint256 target = 5_000;
        uint256 max = 6_000;

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), 1);

        vm.prank(user);
        vm.expectRevert("!keeper");
        debtAllocatorKeeper.setStrategyDebtRatio(address(vault), address(strategy), target, max);

        vm.prank(brain);
        debtAllocatorKeeper.setKeeper(user, true);

        vm.prank(user);
        vm.expectRevert("!allowed");
        debtAllocatorKeeper.setStrategyDebtRatio(address(vault), address(strategy), target, max);

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);

        vm.prank(user);
        vm.expectRevert("!manager");
        debtAllocatorKeeper.setStrategyDebtRatio(address(vault), address(strategy), target, max);

        vm.prank(brain);
        debtAllocator.setManager(address(debtAllocatorKeeper), true);

        vm.prank(user);
        debtAllocatorKeeper.setStrategyDebtRatio(address(vault), address(strategy), target, max);

        DebtAllocator.StrategyConfig memory strategyConfig =
            debtAllocator.getStrategyConfig(address(vault), address(strategy));
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);
    }

    function test_set_strategy_debt_ratio_default_max() public {
        uint256 target = 2_000;

        vm.startPrank(brain);
        debtAllocator.setMinimumChange(address(vault), 1);
        debtAllocator.setManager(address(debtAllocatorKeeper), true);
        debtAllocatorKeeper.setKeeper(brain, true);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);
        debtAllocatorKeeper.setStrategyDebtRatio(address(vault), address(strategy), target);
        vm.stopPrank();

        DebtAllocator.StrategyConfig memory strategyConfig =
            debtAllocator.getStrategyConfig(address(vault), address(strategy));
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, (target * 12) / 10);
    }

    function test_multicall() public {
        MockStrategy secondStrategy = createStrategy(address(asset));
        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        vm.startPrank(daddy);
        vault.add_strategy(address(strategy));
        vault.add_strategy(address(secondStrategy));
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);
        vault.update_max_debt_for_strategy(address(secondStrategy), MAX_INT);
        vault.add_role(address(debtAllocator), Roles.DEBT_MANAGER);
        vm.stopPrank();

        vm.startPrank(brain);
        debtAllocator.setMinimumChange(address(vault), 1);
        debtAllocator.setManager(address(debtAllocatorKeeper), true);
        debtAllocator.setKeeper(address(debtAllocatorKeeper), true);
        vm.stopPrank();

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSignature(
            "setStrategyDebtRatio(address,address,uint256,uint256)", address(vault), address(strategy), 4_000, 4_000
        );
        calls[1] = abi.encodeWithSignature(
            "setStrategyDebtRatio(address,address,uint256)", address(vault), address(secondStrategy), 2_000
        );
        calls[2] = abi.encodeCall(debtAllocatorKeeper.update_debt, (address(vault), address(strategy), amount / 2));
        calls[3] =
            abi.encodeCall(debtAllocatorKeeper.update_debt, (address(vault), address(secondStrategy), amount / 2));

        vm.prank(user);
        vm.expectRevert("!keeper");
        debtAllocatorKeeper.multicall(calls);

        vm.prank(brain);
        debtAllocatorKeeper.setKeeper(user, true);

        vm.prank(user);
        vm.expectRevert("!allowed");
        debtAllocatorKeeper.multicall(calls);

        vm.prank(brain);
        debtAllocatorKeeper.setAllowedVault(address(vault), true);

        vm.prank(user);
        debtAllocatorKeeper.multicall(calls);

        DebtAllocator.StrategyConfig memory strategyConfig =
            debtAllocator.getStrategyConfig(address(vault), address(strategy));
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 4_000);
        assertEq(strategyConfig.maxRatio, 4_000);

        strategyConfig = debtAllocator.getStrategyConfig(address(vault), address(secondStrategy));
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 2_000);
        assertEq(strategyConfig.maxRatio, 2_400);

        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), amount);
    }
}
