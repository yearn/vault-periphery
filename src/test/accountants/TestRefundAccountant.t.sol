// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MockTokenizedStrategy} from "../../Mocks/MockTokenizedStrategy.sol";
import {Setup, Accountant, IVault, Roles, MockStrategy, TestAccountant} from "./TestAccountant.t.sol";
import {RefundAccountant} from "../../accountants/RefundAccountant.sol";

contract TestRefundAccountant is TestAccountant {
    event UpdateRefund(
        address indexed vault,
        address indexed strategy,
        uint256 amount
    );

    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 current_debt,
        uint256 protocol_fees,
        uint256 total_fees,
        uint256 total_refunds
    );

    RefundAccountant public refundAccountant;

    function setUp() public override {
        super.setUp();

        refundAccountant = new RefundAccountant(
            daddy,
            feeRecipient,
            100,
            1000,
            0,
            0,
            10000,
            0
        );

        accountant = Accountant(address(refundAccountant));
    }

    function test_add_reward_refund() public {
        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);

        uint256 amount = 1e18;

        vm.prank(daddy);
        vm.expectRevert("not added");
        refundAccountant.setRefund(address(vault), address(strategy), amount);

        vm.prank(daddy);
        refundAccountant.addVault(address(vault));

        vm.prank(daddy);
        vm.expectRevert("!active");
        refundAccountant.setRefund(address(vault), address(strategy), amount);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdateRefund(address(vault), address(strategy), amount);
        refundAccountant.setRefund(address(vault), address(strategy), amount);

        assertEq(
            refundAccountant.refund(address(vault), address(strategy)),
            amount
        );

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdateRefund(address(vault), address(strategy), 0);
        refundAccountant.setRefund(address(vault), address(strategy), 0);

        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);
    }

    function test_reward_refund() public {
        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);

        uint256 amount = 1e18;
        vm.prank(daddy);
        refundAccountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdateRefund(address(vault), address(strategy), amount);
        refundAccountant.setRefund(address(vault), address(strategy), amount);

        assertEq(
            refundAccountant.refund(address(vault), address(strategy)),
            amount
        );

        vm.prank(daddy);
        vault.set_accountant(address(refundAccountant));

        deal(address(asset), user, amount * 2);
        uint256 userBalance = asset.balanceOf(user);
        uint256 toDeposit = userBalance / 2;

        // Deposit into vault
        vm.prank(user);
        asset.approve(address(vault), toDeposit);

        vm.prank(user);
        vault.deposit(toDeposit, user);

        // Fund the accountant for a refund. Over fund to make sure it only sends amount.
        vm.prank(user);
        asset.transfer(address(refundAccountant), userBalance - toDeposit);

        assertEq(vault.totalAssets(), toDeposit);
        assertEq(vault.totalIdle(), toDeposit);
        assertEq(vault.profitUnlockingRate(), 0);
        assertEq(vault.fullProfitUnlockDate(), 0);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, amount);
        vault.process_report(address(strategy));

        assertEq(vault.totalAssets(), amount + toDeposit);
        assertEq(vault.totalIdle(), amount + toDeposit);
        assertTrue(vault.profitUnlockingRate() > 0);
        assertTrue(vault.fullProfitUnlockDate() > 0);

        // Make sure the amounts got reset.
        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);
        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = refundAccountant.report(
            address(strategy),
            0,
            0
        );
        assertEq(fees, 0);
        assertEq(refunds, 0);
    }

    function test_reward_refund__with_gain() public {
        MockTokenizedStrategy tokenized = deployMockTokenized(
            "tokenized",
            10_000
        );

        // Set performance fee to 10% and 0 management fee
        vm.prank(daddy);
        refundAccountant.updateDefaultConfig(0, 1_000, 0, 10_000, 10_000, 0);
        assertEq(
            refundAccountant.refund(address(vault), address(tokenized)),
            0
        );

        vm.prank(daddy);
        refundAccountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(tokenized));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(tokenized), MAX_INT);

        deal(address(asset), user, 1e18);
        uint256 userBalance = asset.balanceOf(user);
        uint256 toDeposit = userBalance / 2;

        uint256 refund = toDeposit / 10;
        uint256 gain = toDeposit / 10;
        uint256 loss = 0;

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdateRefund(address(vault), address(tokenized), refund);
        refundAccountant.setRefund(address(vault), address(tokenized), refund);

        assertEq(
            refundAccountant.refund(address(vault), address(tokenized)),
            refund
        );

        vm.prank(daddy);
        vault.set_accountant(address(refundAccountant));

        // Deposit into vault
        vm.prank(user);
        asset.approve(address(vault), toDeposit);

        vm.prank(user);
        vault.deposit(toDeposit, user);

        // Give strategy debt.
        provideStrategyWithDebt(vault, address(tokenized), toDeposit);

        // simulate profit.
        vm.prank(user);
        asset.transfer(address(tokenized), gain);
        vm.prank(management);
        tokenized.report();

        // Fund the accountant for a refund. Over fund to make sure it only sends amount.
        vm.prank(user);
        asset.transfer(address(refundAccountant), refund);

        assertEq(vault.totalAssets(), toDeposit);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), toDeposit);
        assertEq(vault.profitUnlockingRate(), 0);
        assertEq(vault.fullProfitUnlockDate(), 0);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit StrategyReported(
            address(tokenized),
            gain,
            0,
            toDeposit + gain,
            0,
            gain / 10,
            refund
        );
        vault.process_report(address(tokenized));

        assertEq(vault.totalAssets(), refund + toDeposit + gain);
        assertEq(vault.totalIdle(), refund);
        assertTrue(vault.profitUnlockingRate() > 0);
        assertTrue(vault.fullProfitUnlockDate() > 0);

        // Make sure the amounts got reset.
        assertEq(
            refundAccountant.refund(address(vault), address(tokenized)),
            0
        );
        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = refundAccountant.report(
            address(tokenized),
            0,
            0
        );
        assertEq(fees, 0);
        assertEq(refunds, 0);
    }

    function test_reward_refund__with_loss__and_refund() public {
        // Set refund ratio to 100%
        vm.prank(daddy);
        refundAccountant.updateDefaultConfig(
            0,
            1_000,
            10_000,
            10_000,
            10_000,
            10_000
        );
        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);

        vm.prank(daddy);
        refundAccountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        deal(address(asset), user, 1e18);
        uint256 userBalance = 1e18;
        uint256 toDeposit = userBalance / 2;

        uint256 refund = toDeposit / 10;
        uint256 gain = 0;
        uint256 loss = toDeposit / 10;

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdateRefund(address(vault), address(strategy), refund);
        refundAccountant.setRefund(address(vault), address(strategy), refund);

        assertEq(
            refundAccountant.refund(address(vault), address(strategy)),
            refund
        );

        vm.prank(daddy);
        vault.set_accountant(address(refundAccountant));

        // Deposit into vault
        vm.prank(user);
        asset.approve(address(vault), toDeposit);

        vm.prank(user);
        vault.deposit(toDeposit, user);

        // Give strategy debt.
        provideStrategyWithDebt(vault, address(strategy), toDeposit);

        // simulate loss.
        vm.prank(address(strategy));
        asset.transfer(user, loss);

        // Fund the accountant for a refund. Over fund to make sure it only sends amount.
        vm.prank(user);
        asset.transfer(address(refundAccountant), refund + loss);

        assertEq(vault.totalAssets(), toDeposit);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), toDeposit);
        assertEq(vault.profitUnlockingRate(), 0);
        assertEq(vault.fullProfitUnlockDate(), 0);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit StrategyReported(
            address(strategy),
            gain,
            loss,
            toDeposit - loss,
            0,
            0,
            refund + loss
        );
        vault.process_report(address(strategy));

        assertEq(vault.totalAssets(), refund + toDeposit);
        assertEq(vault.totalIdle(), refund + loss);
        assertTrue(vault.profitUnlockingRate() > 0);
        assertTrue(vault.fullProfitUnlockDate() > 0);

        // Make sure the amounts got reset.
        assertEq(refundAccountant.refund(address(vault), address(strategy)), 0);
        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = refundAccountant.report(
            address(strategy),
            0,
            0
        );
        assertEq(fees, 0);
        assertEq(refunds, 0);
    }
}
