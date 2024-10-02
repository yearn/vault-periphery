// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, DebtAllocator, IVault, Roles, MockStrategy} from "../utils/Setup.sol";

import "forge-std/console2.sol";

contract TestDebtAllocator is Setup {
    IVault public vault;
    MockStrategy public strategy;

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
    }

    function test_setup() public {
        assertEq(debtAllocator.governance(), brain);
        assertTrue(debtAllocator.keepers(brain));
        assertEq(debtAllocator.maxAcceptableBaseFee(), MAX_INT);
        assertEq(debtAllocator.minimumWait(), 6 hours);
        assertFalse(debtAllocator.managers(brain));

        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 0);
        assertEq(strategyConfig.maxRatio, 0);
        assertEq(strategyConfig.lastUpdate, 0);

        (bool shouldUpdate, bytes memory callData) = debtAllocator
            .shouldUpdateDebt(address(vault), address(strategy));
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("!added"));
    }

    function test_set_keepers() public {
        assertTrue(debtAllocator.keepers(brain));
        assertFalse(debtAllocator.keepers(user));

        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocator.setKeeper(user, true);

        vm.prank(brain);
        debtAllocator.setKeeper(user, true);

        assertTrue(debtAllocator.keepers(user));

        vm.prank(brain);
        debtAllocator.setKeeper(brain, false);

        assertFalse(debtAllocator.keepers(brain));
    }

    function test_set_managers() public {
        assertFalse(debtAllocator.managers(brain));
        assertFalse(debtAllocator.managers(user));

        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocator.setManager(user, true);

        vm.prank(brain);
        debtAllocator.setManager(user, true);

        assertTrue(debtAllocator.managers(user));

        vm.prank(brain);
        debtAllocator.setManager(user, false);

        assertFalse(debtAllocator.managers(user));
    }

    function test_set_minimum_change() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(debtAllocator.minimumChange(address(vault)), 0);

        uint256 minimum = 1e17;

        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocator.setMinimumChange(address(vault), minimum);

        vm.prank(brain);
        vm.expectRevert("zero change");
        debtAllocator.setMinimumChange(address(vault), 0);

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        assertEq(debtAllocator.minimumChange(address(vault)), minimum);
    }

    function test_set_minimum_wait() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(debtAllocator.minimumWait(), 6 hours);

        uint256 minimum = 1e17;

        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocator.setMinimumWait(minimum);

        vm.prank(brain);
        debtAllocator.setMinimumWait(minimum);

        assertEq(debtAllocator.minimumWait(), minimum);
    }

    function test_set_max_debt_update_loss() public {
        assertEq(debtAllocator.maxDebtUpdateLoss(), 1);

        uint256 max = 1_000;

        vm.prank(user);
        vm.expectRevert("!governance");
        debtAllocator.setMaxDebtUpdateLoss(max);

        vm.prank(brain);
        vm.expectRevert("higher than max");
        debtAllocator.setMaxDebtUpdateLoss(10_001);

        vm.prank(brain);
        debtAllocator.setMaxDebtUpdateLoss(max);

        assertEq(debtAllocator.maxDebtUpdateLoss(), max);
    }

    function test_set_ratios() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);

        uint256 minimum = 1e17;
        uint256 max = 6_000;
        uint256 target = 5_000;

        vm.prank(user);
        vm.expectRevert("!manager");
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            max
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        vm.expectRevert("!minimum");
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            max
        );

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        vm.prank(brain);
        vm.expectRevert("max too high");
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            10_001
        );

        vm.prank(brain);
        vm.expectRevert("max ratio");
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            max + 1,
            max
        );

        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            max
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        MockStrategy newStrategy = createStrategy(address(asset));
        vm.prank(daddy);
        vault.add_strategy(address(newStrategy));

        vm.prank(brain);
        vm.expectRevert("ratio too high");
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(newStrategy),
            10_000,
            10_000
        );

        target = 8_000;
        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, (target * 12) / 10);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);
    }

    function test_increase_debt_ratio() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);

        uint256 minimum = 1e17;
        uint256 target = 5_000;
        uint256 increase = 5_000;
        uint256 max = (target * 12) / 10;

        vm.prank(user);
        vm.expectRevert("!manager");
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            increase
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        vm.expectRevert("!minimum");
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            increase
        );

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        vm.prank(brain);
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            increase
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        MockStrategy newStrategy = createStrategy(address(asset));
        vm.prank(daddy);
        vault.add_strategy(address(newStrategy));

        vm.prank(brain);
        vm.expectRevert("ratio too high");
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(newStrategy),
            5_001
        );

        target = 8_000;
        max = (target * 12) / 10;
        increase = 3_000;
        vm.prank(brain);
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            increase
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        target = 10_000;
        max = 10_000;
        increase = 2_000;
        vm.prank(brain);
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            increase
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);
    }

    function test_decrease_debt_ratio() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);

        uint256 minimum = 1e17;
        uint256 target = 5_000;
        uint256 max = (target * 12) / 10;

        vm.prank(daddy);
        vault.add_strategy(address(strategy));
        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        // Underflow
        vm.prank(brain);
        vm.expectRevert();
        debtAllocator.decreaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            target
        );

        // Add the target
        vm.prank(brain);
        debtAllocator.increaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            target
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        target = 2_000;
        max = (target * 12) / 10;
        uint256 decrease = 3_000;

        vm.prank(user);
        vm.expectRevert("!manager");
        debtAllocator.decreaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            decrease
        );

        vm.prank(brain);
        debtAllocator.decreaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            decrease
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        target = 0;
        max = 0;
        decrease = 2_000;
        vm.prank(brain);
        debtAllocator.decreaseStrategyDebtRatio(
            address(vault),
            address(strategy),
            decrease
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);
    }

    function test_should_update_debt() public {
        vm.prank(brain);
        debtAllocator.setMinimumWait(0);

        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 0);
        assertEq(strategyConfig.maxRatio, 0);
        assertEq(strategyConfig.lastUpdate, 0);

        vm.prank(daddy);
        vault.add_role(address(debtAllocator), Roles.DEBT_MANAGER);

        (bool shouldUpdate, bytes memory callData) = debtAllocator
            .shouldUpdateDebt(address(vault), address(strategy));
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("!added"));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        uint256 minimum = 1;
        uint256 target = 5_000;
        uint256 max = 5_000;

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            max
        );

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                debtAllocator.update_debt.selector,
                address(vault),
                address(strategy),
                amount / 2
            )
        );

        assertFalse(debtAllocator.isPaused(address(vault)));
        vm.prank(brain);
        debtAllocator.setPaused(address(vault), true);
        assertTrue(debtAllocator.isPaused(address(vault)));

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Paused"));

        vm.prank(brain);
        debtAllocator.setPaused(address(vault), false);
        assertFalse(debtAllocator.isPaused(address(vault)));

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                debtAllocator.update_debt.selector,
                address(vault),
                address(strategy),
                amount / 2
            )
        );

        vm.prank(brain);
        debtAllocator.update_debt(
            address(vault),
            address(strategy),
            amount / 2
        );

        skip(10);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target + 1,
            target + 1
        );

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                debtAllocator.update_debt.selector,
                address(vault),
                address(strategy),
                (amount * 5_001) / 10_000
            )
        );

        vm.prank(brain);
        debtAllocator.setMinimumWait(MAX_INT);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("min wait"));

        vm.prank(brain);
        debtAllocator.setMinimumWait(0);

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), amount / 2);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );

        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                debtAllocator.update_debt.selector,
                address(vault),
                address(strategy),
                (amount * 5_001) / 10_000
            )
        );

        vm.prank(daddy);
        vault.set_minimum_total_idle(vault.totalIdle());

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("No Idle"));

        vm.prank(daddy);
        vault.set_minimum_total_idle(0);

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), 1e30);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), 1);

        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target / 2,
            target / 2
        );

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                debtAllocator.update_debt.selector,
                address(vault),
                address(strategy),
                amount / 4
            )
        );
    }

    function test_remove_strategy() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 0);
        assertEq(strategyConfig.maxRatio, 0);
        assertEq(strategyConfig.lastUpdate, 0);

        uint256 minimum = 1;
        uint256 max = 6_000;
        uint256 target = 5_000;

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), minimum);

        vm.prank(brain);
        debtAllocator.setStrategyDebtRatio(
            address(vault),
            address(strategy),
            target,
            max
        );

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(strategyConfig.lastUpdate, 0);

        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        skip(60 * 60 * 7);

        (bool shouldUpdate, bytes memory callData) = debtAllocator
            .shouldUpdateDebt(address(vault), address(strategy));
        assertTrue(shouldUpdate);

        vm.prank(user);
        vm.expectRevert("!manager");
        debtAllocator.removeStrategy(address(vault), address(strategy));

        vm.prank(brain);
        debtAllocator.removeStrategy(address(vault), address(strategy));

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertFalse(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 0);
        assertEq(strategyConfig.maxRatio, 0);
        assertEq(strategyConfig.lastUpdate, 0);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), 0);

        (shouldUpdate, callData) = debtAllocator.shouldUpdateDebt(
            address(vault),
            address(strategy)
        );
        assertFalse(shouldUpdate);
    }

    function test_update_debt() public {
        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertFalse(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 0);
        assertEq(strategyConfig.maxRatio, 0);
        assertEq(strategyConfig.lastUpdate, 0);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        assertEq(vault.totalIdle(), amount);
        assertEq(vault.totalDebt(), 0);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        vm.prank(user);
        vm.expectRevert("!keeper");
        debtAllocator.update_debt(address(vault), address(strategy), amount);

        vm.prank(brain);
        vm.expectRevert("not allowed");
        debtAllocator.update_debt(address(vault), address(strategy), amount);

        vm.prank(daddy);
        vault.add_role(
            address(debtAllocator),
            Roles.DEBT_MANAGER | Roles.REPORTING_MANAGER
        );

        vm.prank(brain);
        debtAllocator.update_debt(address(vault), address(strategy), amount);

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertEq(strategyConfig.lastUpdate, block.timestamp);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), amount);

        vm.prank(brain);
        debtAllocator.setKeeper(user, true);

        skip(10);

        vm.prank(user);
        debtAllocator.update_debt(address(vault), address(strategy), 0);

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertEq(strategyConfig.lastUpdate, block.timestamp);
        assertEq(vault.totalIdle(), amount);
        assertEq(vault.totalDebt(), 0);
    }
}
