// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, Roles, IVault, MockTokenized} from "./utils/Setup.sol";

contract TestKeeper is Setup {
    IVault public vault;
    MockTokenized public strategy;

    function setUp() public override {
        super.setUp();

        vault = createVault(address(asset), daddy, MAX_INT, WEEK, "", "VV3");
        strategy = deployMockTokenized("MockTokenized", 1000); // 10% APR

        asset.mint(user, 1000e18);
    }

    function test_keeper() public {
        uint256 amount = 1000e18;
        uint256 depositAmount = amount / 2;

        // Revert on vault
        vm.prank(address(keeper));
        vm.expectRevert("not allowed");
        vault.process_report(address(strategy));

        vm.prank(user);
        vm.expectRevert("not allowed");
        keeper.process_report(address(vault), address(strategy));

        // Add strategy and set keeper role
        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.set_role(address(keeper), Roles.REPORTING_MANAGER);

        // Deposit into strategy
        vm.startPrank(user);
        asset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, address(vault));
        vm.stopPrank();

        // Process report
        vm.prank(user);
        (uint256 profit, uint256 loss) = keeper.process_report(
            address(vault),
            address(strategy)
        );

        assertEq(profit, depositAmount);
        assertEq(loss, 0);

        // Transfer more assets to strategy
        vm.prank(user);
        asset.transfer(address(strategy), depositAmount);

        // Set keeper to user
        vm.prank(management);
        strategy.setKeeper(user);

        // Revert on wrong keeper
        vm.prank(address(keeper));
        vm.expectRevert("!keeper");
        strategy.report();

        vm.prank(user);
        vm.expectRevert("!keeper");
        keeper.report(address(strategy));

        // Set keeper back to keeper contract
        vm.prank(management);
        strategy.setKeeper(address(keeper));

        // Report
        vm.prank(user);
        (profit, loss) = keeper.report(address(strategy));

        assertEq(profit, depositAmount);
        assertEq(loss, 0);
    }
}
