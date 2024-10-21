// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, DebtAllocator, IVault, Roles, MockStrategy} from "../utils/Setup.sol";
import {DebtOptimizerApplicator} from "../../debtAllocators/DebtOptimizerApplicator.sol";

contract TestDebtOptimizerApplicator is Setup {
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
        assertFalse(debtOptimizerApplicator.managers(brain));
        assertEq(
            address(debtOptimizerApplicator.debtAllocator()),
            address(debtAllocator)
        );
    }

    function test_set_managers() public {
        assertFalse(debtOptimizerApplicator.managers(brain));
        assertFalse(debtOptimizerApplicator.managers(user));

        vm.prank(user);
        vm.expectRevert("!governance");
        debtOptimizerApplicator.setManager(user, true);

        vm.prank(brain);
        debtOptimizerApplicator.setManager(user, true);

        assertTrue(debtOptimizerApplicator.managers(user));

        vm.prank(brain);
        debtOptimizerApplicator.setManager(user, false);

        assertFalse(debtOptimizerApplicator.managers(user));
    }

    function test_set_ratios() public {
        uint256 max = 6_000;
        uint256 target = 5_000;
        DebtOptimizerApplicator.StrategyDebtRatio[]
            memory strategyDebtRatios = new DebtOptimizerApplicator.StrategyDebtRatio[](
                1
            );
        strategyDebtRatios[0] = DebtOptimizerApplicator.StrategyDebtRatio(
            address(strategy),
            target,
            max
        );

        vm.prank(brain);
        debtAllocator.setManager(address(debtOptimizerApplicator), true);

        vm.prank(brain);
        debtAllocator.setMinimumChange(address(vault), 1);

        vm.prank(user);
        vm.expectRevert("!manager");
        debtOptimizerApplicator.setStrategyDebtRatios(
            address(vault),
            strategyDebtRatios
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        debtOptimizerApplicator.setStrategyDebtRatios(
            address(vault),
            strategyDebtRatios
        );

        DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
            .getStrategyConfig(address(vault), address(strategy));
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, target);
        assertEq(strategyConfig.maxRatio, max);
        assertEq(debtAllocator.totalDebtRatio(address(vault)), target);

        MockStrategy newStrategy = createStrategy(address(asset));
        vm.prank(daddy);
        vault.add_strategy(address(newStrategy));

        DebtOptimizerApplicator.StrategyDebtRatio[]
            memory newStrategyDebtRatios = new DebtOptimizerApplicator.StrategyDebtRatio[](
                1
            );
        newStrategyDebtRatios[0] = DebtOptimizerApplicator.StrategyDebtRatio(
            address(newStrategy),
            10_000,
            10_000
        );

        vm.prank(brain);
        vm.expectRevert("ratio too high");
        debtOptimizerApplicator.setStrategyDebtRatios(
            address(vault),
            newStrategyDebtRatios
        );

        DebtOptimizerApplicator.StrategyDebtRatio[]
            memory updatedStrategyDebtRatios = new DebtOptimizerApplicator.StrategyDebtRatio[](
                2
            );
        updatedStrategyDebtRatios[0] = DebtOptimizerApplicator
            .StrategyDebtRatio(address(strategy), 8_000, 9_000);
        updatedStrategyDebtRatios[1] = DebtOptimizerApplicator
            .StrategyDebtRatio(address(newStrategy), 2_000, 0);

        vm.prank(brain);
        debtOptimizerApplicator.setStrategyDebtRatios(
            address(vault),
            updatedStrategyDebtRatios
        );

        assertEq(debtAllocator.totalDebtRatio(address(vault)), 10_000);

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(strategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 8_000);
        assertEq(strategyConfig.maxRatio, 9_000);

        strategyConfig = debtAllocator.getStrategyConfig(
            address(vault),
            address(newStrategy)
        );
        assertTrue(strategyConfig.added);
        assertEq(strategyConfig.targetRatio, 2_000);
        assertEq(strategyConfig.maxRatio, 2_400); // 2_000 * 1.2
    }

    function test_set_ratios_multicall(uint8 _vaultCount) public {
        vm.assume(_vaultCount > 0);

        vm.prank(brain);
        debtAllocator.setManager(address(debtOptimizerApplicator), true);

        bytes[] memory multicallData = new bytes[](_vaultCount);
        IVault[] memory vaults = new IVault[](_vaultCount);
        for (uint8 i; i < _vaultCount; ++i) {
            vaults[i] = createVault(
                address(asset),
                daddy,
                MAX_INT,
                WEEK,
                string(abi.encodePacked("Test Vault ", i)),
                "tvTEST"
            );

            vm.prank(brain);
            debtAllocator.setMinimumChange(address(vaults[i]), 1);

            DebtOptimizerApplicator.StrategyDebtRatio[]
                memory strategyDebtRatios = new DebtOptimizerApplicator.StrategyDebtRatio[](
                    1
                );
            strategyDebtRatios[0] = DebtOptimizerApplicator.StrategyDebtRatio(
                address(strategy),
                2_000,
                (i % 2 == 0) ? 0 : 3_000 // alternate between setting and not setting maxDebt
            );

            multicallData[i] = abi.encodeCall(
                debtOptimizerApplicator.setStrategyDebtRatios,
                (address(vaults[i]), strategyDebtRatios)
            );
        }

        vm.prank(user);
        vm.expectRevert("!manager");
        debtOptimizerApplicator.multicall(multicallData);

        vm.prank(brain);
        debtOptimizerApplicator.multicall(multicallData);

        for (uint8 i; i < _vaultCount; ++i) {
            DebtAllocator.StrategyConfig memory strategyConfig = debtAllocator
                .getStrategyConfig(address(vaults[i]), address(strategy));
            assertTrue(strategyConfig.added);
            assertEq(strategyConfig.targetRatio, 2_000);
            assertEq(
                strategyConfig.maxRatio,
                (i % 2 == 0) ? (2_000 * 12) / 10 : 3_000
            );
        }
    }
}
