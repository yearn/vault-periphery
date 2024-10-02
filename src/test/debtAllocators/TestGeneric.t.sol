// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, GenericDebtAllocator, GenericDebtAllocatorFactory, IVault, Roles, MockStrategy} from "../utils/Setup.sol";

contract TestGenericDebtAllocator is Setup {
    event UpdateStrategyDebtRatio(
        address indexed strategy,
        uint256 newTargetRatio,
        uint256 newMaxRatio,
        uint256 newTotalDebtRatio
    );

    /// @notice An even emitted when the paused status is updated.
    event UpdatePaused(bool indexed status);

    /// @notice An event emitted when the minimum time to wait is updated.
    event UpdateMinimumWait(uint256 newMinimumWait);

    /// @notice An event emitted when the minimum change is updated.
    event UpdateMinimumChange(uint256 newMinimumChange);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateManager(address indexed manager, bool allowed);

    /// @notice An event emitted when the max debt update loss is updated.
    event UpdateMaxDebtUpdateLoss(uint256 newMaxDebtUpdateLoss);

    /// @notice An event emitted when a strategy is added or removed.
    event StrategyChanged(address indexed strategy, Status status);

    /// @notice An event emitted when the max base fee is updated.
    event UpdateMaxAcceptableBaseFee(uint256 newMaxAcceptableBaseFee);

    /// @notice Status when a strategy is added or removed from the allocator.
    enum Status {
        NULL,
        ADDED,
        REMOVED
    }

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

        genericAllocator = GenericDebtAllocator(
            genericAllocatorFactory.newGenericDebtAllocator(
                address(vault),
                brain,
                1e18
            )
        );
    }

    function test_setup() public {
        vm.prank(user);
        genericAllocator = GenericDebtAllocator(
            genericAllocatorFactory.newGenericDebtAllocator(
                address(vault),
                brain,
                1e18
            )
        );

        assertEq(genericAllocator.maxAcceptableBaseFee(), type(uint256).max);
        assertTrue(genericAllocator.keepers(brain));
        assertFalse(genericAllocator.managers(brain));
        assertEq(genericAllocator.vault(), address(vault));
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);
        assertEq(genericAllocator.totalDebtRatio(), 0);
        (bool shouldUpdate, bytes memory callData) = genericAllocator
            .shouldUpdateDebt(address(strategy));
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("!added"));
    }

    function test_set_keepers() public {
        assertTrue(genericAllocator.keepers(brain));
        assertFalse(genericAllocator.keepers(user));

        vm.prank(user);
        vm.expectRevert("!governance");
        genericAllocator.setKeeper(user, true);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateKeeper(user, true);
        genericAllocator.setKeeper(user, true);

        assertTrue(genericAllocator.keepers(user));

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateKeeper(brain, false);
        genericAllocator.setKeeper(brain, false);

        assertFalse(genericAllocator.keepers(brain));
    }

    function test_set_managers() public {
        assertFalse(genericAllocator.managers(brain));
        assertFalse(genericAllocator.managers(user));

        vm.prank(user);
        vm.expectRevert("!governance");
        genericAllocator.setManager(user, true);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateManager(user, true);
        genericAllocator.setManager(user, true);

        assertTrue(genericAllocator.managers(user));

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateManager(user, false);
        genericAllocator.setManager(user, false);

        assertFalse(genericAllocator.managers(user));
    }

    function test_set_minimum_change() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);
        assertNotEq(genericAllocator.minimumChange(), 0);

        uint256 minimum = 1e17;

        vm.prank(user);
        vm.expectRevert("!governance");
        genericAllocator.setMinimumChange(minimum);

        vm.prank(brain);
        vm.expectRevert("zero change");
        genericAllocator.setMinimumChange(0);

        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateMinimumChange(minimum);
        genericAllocator.setMinimumChange(minimum);

        assertEq(genericAllocator.minimumChange(), minimum);
    }

    function test_set_minimum_wait() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);
        assertEq(genericAllocator.minimumWait(), 0);

        uint256 minimum = 1e17;

        vm.prank(user);
        vm.expectRevert("!governance");
        genericAllocator.setMinimumWait(minimum);

        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateMinimumWait(minimum);
        genericAllocator.setMinimumWait(minimum);

        assertEq(genericAllocator.minimumWait(), minimum);
    }

    function test_set_max_debt_update_loss() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);
        assertEq(genericAllocator.maxDebtUpdateLoss(), 1);

        uint256 maximum = 542;

        vm.prank(user);
        vm.expectRevert("!governance");
        genericAllocator.setMaxDebtUpdateLoss(maximum);

        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateMaxDebtUpdateLoss(maximum);
        genericAllocator.setMaxDebtUpdateLoss(maximum);

        assertEq(genericAllocator.maxDebtUpdateLoss(), maximum);
    }

    function test_set_ratios() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        uint256 minimum = 1e17;
        uint256 max = 6_000;
        uint256 target = 5_000;

        vm.prank(user);
        vm.expectRevert("!manager");
        genericAllocator.setStrategyDebtRatio(address(strategy), target, max);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        vm.expectRevert("max too high");
        genericAllocator.setStrategyDebtRatio(
            address(strategy),
            target,
            10_001
        );

        vm.prank(brain);
        vm.expectRevert("max ratio");
        genericAllocator.setStrategyDebtRatio(address(strategy), max + 1, max);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit StrategyChanged(address(strategy), Status.ADDED);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.setStrategyDebtRatio(address(strategy), target, max);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(config.lastUpdate, 0);

        MockStrategy newStrategy = createStrategy(address(asset));

        vm.prank(daddy);
        vault.add_strategy(address(newStrategy));

        vm.prank(brain);
        vm.expectRevert("ratio too high");
        genericAllocator.setStrategyDebtRatio(
            address(newStrategy),
            10_000,
            10_000
        );

        target = 8_000;
        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(
            address(strategy),
            target,
            (target * 12) / 10,
            target
        );
        genericAllocator.setStrategyDebtRatio(address(strategy), target);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, (target * 12) / 10);
        assertEq(config.lastUpdate, 0);
    }

    function test_increase_debt_ratio() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        uint256 minimum = 1e17;
        uint256 target = 5_000;
        uint256 increase = 5_000;
        uint256 max = (target * 12) / 10;

        vm.prank(user);
        vm.expectRevert("!manager");
        genericAllocator.increaseStrategyDebtRatio(address(strategy), increase);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.increaseStrategyDebtRatio(address(strategy), increase);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(config.lastUpdate, 0);

        MockStrategy newStrategy = createStrategy(address(asset));
        vm.prank(daddy);
        vault.add_strategy(address(newStrategy));

        vm.prank(brain);
        vm.expectRevert("ratio too high");
        genericAllocator.increaseStrategyDebtRatio(address(newStrategy), 5_001);

        target = 8_000;
        max = (target * 12) / 10;
        increase = 3_000;
        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.increaseStrategyDebtRatio(address(strategy), increase);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(config.lastUpdate, 0);

        target = 10_000;
        max = 10_000;
        increase = 2_000;
        vm.prank(brain);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.increaseStrategyDebtRatio(address(strategy), increase);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(config.lastUpdate, 0);
    }

    function test_decrease_debt_ratio() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertEq(config.added, false);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        uint256 minimum = 1e17;
        uint256 target = 5_000;
        uint256 max = (target * 12) / 10; // 120% of target

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        genericAllocator.setMinimumChange(minimum);

        // Underflow
        vm.prank(brain);
        vm.expectRevert();
        genericAllocator.decreaseStrategyDebtRatio(address(strategy), target);

        // Add the target
        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.increaseStrategyDebtRatio(address(strategy), target);

        config = genericAllocator.getConfig(address(strategy));
        assertEq(config.added, true);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(genericAllocator.totalDebtRatio(), target);

        target = 2_000;
        max = (target * 12) / 10;
        uint256 decrease = 3_000;

        vm.prank(user);
        vm.expectRevert("!manager");
        genericAllocator.decreaseStrategyDebtRatio(address(strategy), decrease);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.decreaseStrategyDebtRatio(address(strategy), decrease);

        config = genericAllocator.getConfig(address(strategy));
        assertEq(config.added, true);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(genericAllocator.totalDebtRatio(), target);

        target = 0;
        max = 0;
        decrease = 2_000;

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.decreaseStrategyDebtRatio(address(strategy), decrease);

        config = genericAllocator.getConfig(address(strategy));
        assertEq(config.added, true);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(genericAllocator.totalDebtRatio(), 0);
    }

    function test_remove_strategy(uint256 amount) public {
        vm.assume(amount > minFuzzAmount && amount < maxFuzzAmount);
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        uint256 minimum = 1;
        uint256 max = 6_000;
        uint256 target = 5_000;

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(brain);
        genericAllocator.setMinimumChange(minimum);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit StrategyChanged(address(strategy), Status.ADDED);
        vm.expectEmit(false, false, false, true);
        emit UpdateStrategyDebtRatio(address(strategy), target, max, target);
        genericAllocator.setStrategyDebtRatio(address(strategy), target, max);

        assertEq(genericAllocator.totalDebtRatio(), target);
        config = genericAllocator.getConfig(address(strategy));
        assertTrue(config.added);
        assertEq(config.targetRatio, target);
        assertEq(config.maxRatio, max);
        assertEq(config.lastUpdate, 0);

        depositIntoVault(vault, amount);
        vm.prank(daddy);
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );

        (bool shouldUpdate, bytes memory callData) = genericAllocator
            .shouldUpdateDebt(address(strategy));
        assertTrue(shouldUpdate);

        vm.prank(user);
        vm.expectRevert("!manager");
        genericAllocator.removeStrategy(address(strategy));

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit StrategyChanged(address(strategy), Status.REMOVED);
        genericAllocator.removeStrategy(address(strategy));

        assertEq(genericAllocator.totalDebtRatio(), 0);
        config = genericAllocator.getConfig(address(strategy));
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
    }

    function test_should_update_debt(uint256 amount) public {
        vm.assume(amount > minFuzzAmount && amount < maxFuzzAmount);
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        vm.prank(daddy);
        vault.add_role(address(genericAllocator), Roles.DEBT_MANAGER);

        (bool shouldUpdate, bytes memory callData) = genericAllocator
            .shouldUpdateDebt(address(strategy));
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("!added"));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        uint256 minimum = 1;
        uint256 target = 5_000;
        uint256 max = 5_000;

        vm.prank(brain);
        genericAllocator.setMinimumChange(minimum);

        vm.prank(brain);
        genericAllocator.setStrategyDebtRatio(address(strategy), target, max);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        depositIntoVault(vault, amount);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                amount / 2
            )
        );

        vm.prank(brain);
        genericAllocator.update_debt(address(strategy), amount / 2);

        skip(10);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(brain);
        genericAllocator.setStrategyDebtRatio(
            address(strategy),
            target + 10,
            target + 10
        );

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                (amount * 5_010) / 10_000
            )
        );

        vm.prank(brain);
        genericAllocator.setMinimumWait(type(uint256).max);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("min wait"));

        vm.prank(brain);
        genericAllocator.setMinimumWait(0);

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), amount / 2);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                (amount * 5_010) / 10_000
            )
        );

        vm.prank(daddy);
        vault.set_minimum_total_idle(vault.totalIdle());

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("No Idle"));

        vm.prank(daddy);
        vault.set_minimum_total_idle(0);

        vm.prank(brain);
        genericAllocator.setMinimumChange(1e30);

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("Below Min"));

        vm.prank(brain);
        genericAllocator.setMinimumChange(1);

        vm.prank(brain);
        genericAllocator.setStrategyDebtRatio(
            address(strategy),
            target / 2,
            target / 2
        );

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                amount / 4
            )
        );
    }

    function test_update_debt() public {
        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        uint256 amount = 1e18; // Assuming a reasonable amount
        depositIntoVault(vault, amount);

        assertEq(vault.totalIdle(), amount);
        assertEq(vault.totalDebt(), 0);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );

        // This reverts by the allocator
        vm.prank(user);
        vm.expectRevert("!keeper");
        genericAllocator.update_debt(address(strategy), amount);

        // This reverts by the vault
        vm.prank(brain);
        vm.expectRevert("not allowed");
        genericAllocator.update_debt(address(strategy), amount);

        vm.prank(daddy);
        vault.add_role(
            address(genericAllocator),
            Roles.DEBT_MANAGER | Roles.REPORTING_MANAGER
        );

        vm.prank(brain);
        genericAllocator.update_debt(address(strategy), amount);

        config = genericAllocator.getConfig(address(strategy));
        uint256 timestamp = config.lastUpdate;
        assertNotEq(timestamp, 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), amount);

        vm.prank(brain);
        genericAllocator.setKeeper(user, true);

        vm.prank(user);
        genericAllocator.update_debt(address(strategy), 0);

        config = genericAllocator.getConfig(address(strategy));
        assertEq(config.lastUpdate, timestamp);
        assertEq(vault.totalIdle(), amount);
        assertEq(vault.totalDebt(), 0);
    }

    function test_pause() public {
        assertFalse(genericAllocator.paused());

        GenericDebtAllocator.Config memory config = genericAllocator.getConfig(
            address(strategy)
        );
        assertFalse(config.added);
        assertEq(config.targetRatio, 0);
        assertEq(config.maxRatio, 0);
        assertEq(config.lastUpdate, 0);
        assertEq(config.open, 0);

        vm.prank(daddy);
        vault.add_role(address(genericAllocator), Roles.DEBT_MANAGER);

        (bool shouldUpdate, bytes memory callData) = genericAllocator
            .shouldUpdateDebt(address(strategy));
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("!added"));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        uint256 minimum = 1;
        uint256 target = 5_000;
        uint256 max = 5_000;

        vm.prank(brain);
        genericAllocator.setMinimumChange(minimum);

        vm.prank(brain);
        genericAllocator.setStrategyDebtRatio(address(strategy), target, max);

        uint256 amount = 1e18; // Assuming a reasonable amount
        depositIntoVault(vault, amount);

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );

        // Should now want to allocate 50%
        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                amount / 2
            )
        );

        // Pause the allocator
        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdatePaused(true);
        genericAllocator.setPaused(true);

        assertTrue(genericAllocator.paused());

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertFalse(shouldUpdate);
        assertEq(callData, abi.encodePacked("paused"));

        // Unpause
        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdatePaused(false);
        genericAllocator.setPaused(false);

        assertFalse(genericAllocator.paused());

        (shouldUpdate, callData) = genericAllocator.shouldUpdateDebt(
            address(strategy)
        );
        assertTrue(shouldUpdate);
        assertEq(
            callData,
            abi.encodeWithSelector(
                genericAllocator.update_debt.selector,
                address(strategy),
                amount / 2
            )
        );
    }

    // Helper function to deposit into vault
    function depositIntoVault(IVault _vault, uint256 _amount) internal {
        deal(address(asset), address(this), _amount);
        asset.approve(address(_vault), _amount);
        _vault.deposit(_amount, address(this));
    }
}
