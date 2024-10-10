// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, Accountant, IVault, Roles, MockStrategy} from "../utils/Setup.sol";

contract TestAccountant is Setup {
    IVault public vault;
    MockStrategy public strategy;

    function setUp() public virtual override {
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
        assertEq(accountant.feeManager(), daddy);
        assertEq(accountant.futureFeeManager(), address(0));
        assertEq(accountant.feeRecipient(), feeRecipient);
        (
            uint16 managementFee,
            uint16 performanceFee,
            uint16 refundRatio,
            uint16 maxFee,
            uint16 maxGain,
            uint16 maxLoss,
            bool custom
        ) = accountant.defaultConfig();
        assertEq(managementFee, 100);
        assertEq(performanceFee, 1_000);
        assertEq(refundRatio, 0);
        assertEq(maxFee, 0);
        assertEq(maxGain, 10_000);
        assertEq(maxLoss, 0);
        assertFalse(accountant.vaults(address(vault)));
        assertFalse(accountant.useCustomConfig(address(vault)));
        (
            managementFee,
            performanceFee,
            refundRatio,
            maxFee,
            maxGain,
            maxLoss,
            custom
        ) = accountant.customConfig(address(vault));
        assertEq(managementFee, 0);
        assertEq(performanceFee, 0);
        assertEq(refundRatio, 0);
        assertEq(maxFee, 0);
        assertEq(maxGain, 0);
        assertEq(maxLoss, 0);
        assertFalse(custom);
    }

    function test_remove_vault() public {
        assertFalse(accountant.vaults(address(vault)));

        uint16 new_management = 0;
        uint16 new_performance = 1_000;
        uint16 new_refund = 0;
        uint16 new_max_fee = 0;
        uint16 new_max_gain = 10_000;
        uint16 new_max_loss = 0;

        vm.prank(daddy);
        accountant.updateDefaultConfig(
            new_management,
            new_performance,
            new_refund,
            new_max_fee,
            new_max_gain,
            new_max_loss
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertFalse(accountant.vaults(address(vault)));

        vm.prank(daddy);
        accountant.addVault(address(vault));

        assertTrue(accountant.vaults(address(vault)));

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            1_000,
            0
        );
        assertEq(fees, 100);
        assertEq(refunds, 0);

        vm.prank(user);
        vm.expectRevert("!vault manager");
        accountant.removeVault(address(vault));

        vm.prank(daddy);
        accountant.removeVault(address(vault));

        assertFalse(accountant.vaults(address(vault)));

        vm.prank(address(vault));
        vm.expectRevert("vault not added");
        accountant.report(address(strategy), 0, 0);
    }

    function test_remove_vault__non_zero_allomance() public {
        assertFalse(accountant.vaults(address(vault)));

        uint16 new_management = 0;
        uint16 new_performance = 1_000;
        uint16 new_refund = 0;
        uint16 new_max_fee = 0;
        uint16 new_max_gain = 10_000;
        uint16 new_max_loss = 0;

        vm.prank(daddy);
        accountant.updateDefaultConfig(
            new_management,
            new_performance,
            new_refund,
            new_max_fee,
            new_max_gain,
            new_max_loss
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertFalse(accountant.vaults(address(vault)));

        vm.prank(daddy);
        accountant.addVault(address(vault));

        assertTrue(accountant.vaults(address(vault)));

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            1_000,
            0
        );
        assertEq(fees, 100);
        assertEq(refunds, 0);

        vm.prank(address(accountant));
        asset.approve(address(vault), 19);
        assertNotEq(asset.allowance(address(accountant), address(vault)), 0);

        vm.prank(user);
        vm.expectRevert("!vault manager");
        accountant.removeVault(address(vault));

        vm.prank(daddy);
        accountant.removeVault(address(vault));

        assertEq(asset.allowance(address(accountant), address(vault)), 0);
        assertFalse(accountant.vaults(address(vault)));

        vm.prank(address(vault));
        vm.expectRevert("vault not added");
        accountant.report(address(strategy), 0, 0);
    }

    function test_add_vault__vault_manager() public {
        assertFalse(accountant.vaults(address(vault)));

        vm.prank(user);
        vm.expectRevert("!fee manager");
        accountant.setVaultManager(vaultManager);

        vm.prank(daddy);
        accountant.setVaultManager(vaultManager);

        uint16 new_management = 0;
        uint16 new_performance = 1_000;
        uint16 new_refund = 0;
        uint16 new_max_fee = 0;
        uint16 new_max_gain = 10_000;
        uint16 new_max_loss = 0;

        vm.prank(daddy);
        accountant.updateDefaultConfig(
            new_management,
            new_performance,
            new_refund,
            new_max_fee,
            new_max_gain,
            new_max_loss
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        vm.prank(address(vault));
        vm.expectRevert("vault not added");
        accountant.report(address(strategy), 0, 0);

        vm.prank(user);
        vm.expectRevert("!vault manager");
        accountant.addVault(address(vault));

        vm.prank(vaultManager);
        accountant.addVault(address(vault));

        assertTrue(accountant.vaults(address(vault)));

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            1_000,
            0
        );
        assertEq(fees, 100);
        assertEq(refunds, 0);
    }

    function test_set_default_config() public {
        {
            (
                uint16 managementFee,
                uint16 performanceFee,
                uint16 refundRatio,
                uint16 maxFee,
                uint16 maxGain,
                uint16 maxLoss,

            ) = accountant.defaultConfig();
            assertEq(managementFee, 100);
            assertEq(performanceFee, 1_000);
            assertEq(refundRatio, 0);
            assertEq(maxFee, 0);
            assertEq(maxGain, 10_000);
            assertEq(maxLoss, 0);
        }
        uint16 new_management = 20;
        uint16 new_performance = 2_000;
        uint16 new_refund = 13;
        uint16 new_max_fee = 18;
        uint16 new_max_gain = 19;
        uint16 new_max_loss = 27;

        vm.prank(daddy);
        accountant.updateDefaultConfig(
            new_management,
            new_performance,
            new_refund,
            new_max_fee,
            new_max_gain,
            new_max_loss
        );

        (
            uint16 managementFee,
            uint16 performanceFee,
            uint16 refundRatio,
            uint16 maxFee,
            uint16 maxGain,
            uint16 maxLoss,

        ) = accountant.defaultConfig();
        assertEq(managementFee, new_management);
        assertEq(performanceFee, new_performance);
        assertEq(refundRatio, new_refund);
        assertEq(maxFee, new_max_fee);
        assertEq(maxGain, new_max_gain);
        assertEq(maxLoss, new_max_loss);
    }

    function test_distribute() public {
        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        assertEq(vault.balanceOf(user), amount);
        assertEq(vault.balanceOf(address(accountant)), 0);
        assertEq(vault.balanceOf(daddy), 0);
        assertEq(vault.balanceOf(feeRecipient), 0);

        vm.prank(user);
        vault.transfer(address(accountant), amount);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(accountant)), amount);
        assertEq(vault.balanceOf(daddy), 0);
        assertEq(vault.balanceOf(feeRecipient), 0);

        vm.prank(user);
        vm.expectRevert("!recipient");
        accountant.distribute(address(vault));

        vm.prank(daddy);
        accountant.distribute(address(vault));

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(accountant)), 0);
        assertEq(vault.balanceOf(daddy), 0);
        assertEq(vault.balanceOf(feeRecipient), amount);
    }

    function test_redeem_underlying() public {
        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);

        assertEq(vault.balanceOf(user), amount);
        assertEq(vault.balanceOf(address(accountant)), 0);
        assertEq(asset.balanceOf(address(accountant)), 0);

        vm.prank(user);
        vault.transfer(address(accountant), amount);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(accountant)), amount);
        assertEq(asset.balanceOf(address(accountant)), 0);

        vm.prank(user);
        vm.expectRevert("!fee manager");
        accountant.redeemUnderlying(address(vault), amount);

        vm.prank(daddy);
        accountant.redeemUnderlying(address(vault), amount);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(accountant)), 0);
        assertEq(asset.balanceOf(address(accountant)), amount);
    }

    function test_report_profit() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = amount / 10;
        uint256 loss = 0;

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (uint16 _managementFee, uint16 _performanceFee, , , , , ) = accountant
            .defaultConfig();

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(refunds, 0);
    }

    function test_report_no_profit() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = 0;
        uint256 loss = 0;

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (uint16 _managementFee, uint16 _performanceFee, , , , , ) = accountant
            .defaultConfig();

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(refunds, 0);
    }

    function test_report_loss() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = 0;
        uint256 loss = amount / 10;

        vm.prank(daddy);
        accountant.setCustomConfig(
            address(vault),
            200,
            2_000,
            0,
            100,
            0,
            10_000
        );

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            ,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.customConfig(address(vault));

        assertEq(0, fees);
        assertEq(refunds, 0);
    }

    function test_report_refund() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.updateDefaultConfig(200, 2_000, 5_000, 0, 10_000, 10_000);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        uint256 gain = 0;
        uint256 loss = amount / 10;

        // make sure accountant has the funds
        deal(address(asset), address(accountant), loss);

        // Skip a year
        skip(31_556_952);

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            uint16 _refundRatio,
            ,
            ,
            ,

        ) = accountant.defaultConfig();

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_refunds = (loss * _refundRatio) / MAX_BPS;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(expected_refunds, refunds);
        assertEq(
            asset.allowance(address(accountant), address(vault)),
            expected_refunds
        );
    }

    function test_report_refund_not_enough_asset() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.updateDefaultConfig(200, 2_000, 10_000, 0, 10_000, 10_000);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        uint256 gain = 0;
        uint256 loss = amount / 10;

        // make sure accountant has half the funds needed
        deal(address(asset), address(accountant), loss / 2);

        // Skip a year
        skip(31_556_952);

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            ,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.defaultConfig();

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_refunds = loss / 2;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(expected_refunds, refunds);
        assertEq(
            asset.allowance(address(accountant), address(vault)),
            expected_refunds
        );
    }

    function test_report_refund_custom_config() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.setCustomConfig(
            address(vault),
            200,
            2_000,
            5_000,
            0,
            10_000,
            10_000
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        uint256 gain = 0;
        uint256 loss = amount / 10;

        // make sure accountant has the funds
        deal(address(asset), address(accountant), loss);

        // Skip a year
        skip(31_556_952);

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            uint16 _refundRatio,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.customConfig(address(vault));

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_refunds = (loss * _refundRatio) / MAX_BPS;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(expected_refunds, refunds);
        assertEq(
            asset.allowance(address(accountant), address(vault)),
            expected_refunds
        );
    }

    function test_report_refund_not_enough_asset_custom_config() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.setCustomConfig(
            address(vault),
            200,
            2_000,
            10_000,
            0,
            10_000,
            10_000
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        uint256 gain = 0;
        uint256 loss = amount / 10;

        // make sure accountant has half the funds needed
        deal(address(asset), address(accountant), loss / 2);

        // Skip a year
        skip(31_556_952);

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            ,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.customConfig(address(vault));

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_refunds = loss / 2;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(expected_refunds, refunds);
        assertEq(
            asset.allowance(address(accountant), address(vault)),
            expected_refunds
        );
    }

    function test_set_fee_manager() public {
        assertEq(accountant.feeManager(), daddy);
        assertEq(accountant.futureFeeManager(), address(0));

        vm.prank(user);
        vm.expectRevert("!fee manager");
        accountant.setFutureFeeManager(user);

        vm.prank(user);
        vm.expectRevert("not future fee manager");
        accountant.acceptFeeManager();

        vm.prank(daddy);
        vm.expectRevert("not future fee manager");
        accountant.acceptFeeManager();

        vm.prank(daddy);
        vm.expectRevert("ZERO ADDRESS");
        accountant.setFutureFeeManager(address(0));

        vm.prank(daddy);
        accountant.setFutureFeeManager(user);

        assertEq(accountant.futureFeeManager(), user);

        vm.prank(daddy);
        vm.expectRevert("not future fee manager");
        accountant.acceptFeeManager();

        vm.prank(user);
        accountant.acceptFeeManager();

        assertEq(accountant.feeManager(), user);
        assertEq(accountant.futureFeeManager(), address(0));
    }

    function test_set_fee_recipient() public {
        address initialFeeRecipient = accountant.feeRecipient();

        vm.prank(user);
        vm.expectRevert("!fee manager");
        accountant.setFeeRecipient(user);

        vm.prank(feeRecipient);
        vm.expectRevert("!fee manager");
        accountant.setFeeRecipient(user);

        vm.prank(daddy);
        vm.expectRevert("ZERO ADDRESS");
        accountant.setFeeRecipient(address(0));

        vm.prank(daddy);
        accountant.setFeeRecipient(user);

        assertEq(accountant.feeRecipient(), user);
    }

    function test_report_max_fee() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.updateDefaultConfig(200, 2_000, 0, 1_000, 10_000, 10_000);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = amount;
        uint256 loss = 0;

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            ,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.defaultConfig();

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_fees = expected_management_fees +
            expected_performance_fees;
        uint256 max_fees = (amount * _maxFee) / MAX_BPS;

        assertEq(fees, max_fees);
        assertLt(fees, expected_fees);
        assertEq(refunds, 0);
    }

    function test_report_no_profit__custom_config() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.setCustomConfig(address(vault), 200, 2_000, 0, 0, 10_000, 0);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = 0;
        uint256 loss = 0;

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (uint16 _managementFee, uint16 _performanceFee, , , , , ) = accountant
            .customConfig(address(vault));

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        assertEq(expected_management_fees + expected_performance_fees, fees);
        assertEq(refunds, 0);
    }

    function test_report_max_fee__custom_config() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        vm.prank(daddy);
        accountant.setCustomConfig(
            address(vault),
            200,
            2_000,
            0,
            1_000,
            10_000,
            10_000
        );

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = amount;
        uint256 loss = 0;

        vm.prank(address(vault));
        (uint256 fees, uint256 refunds) = accountant.report(
            address(strategy),
            gain,
            loss
        );

        (
            uint16 _managementFee,
            uint16 _performanceFee,
            ,
            uint16 _maxFee,
            ,
            ,

        ) = accountant.customConfig(address(vault));

        // Management fees
        uint256 expected_management_fees = (amount * _managementFee) / MAX_BPS;
        // Perf fees
        uint256 expected_performance_fees = (gain * _performanceFee) / MAX_BPS;

        uint256 expected_fees = expected_management_fees +
            expected_performance_fees;
        uint256 max_fees = (amount * _maxFee) / MAX_BPS;

        assertEq(fees, max_fees);
        assertLt(fees, expected_fees);
        assertEq(refunds, 0);
    }

    function test_report_profit__custom_zero_max_gain__reverts() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        // Set max gain to 1%
        vm.prank(daddy);
        accountant.setCustomConfig(address(vault), 200, 2_000, 0, 100, 1, 0);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip a year
        skip(31_556_952);

        uint256 gain = amount / 10;
        uint256 loss = 0;

        vm.prank(address(vault));
        vm.expectRevert("too much gain");
        accountant.report(address(strategy), gain, loss);
    }

    function test_report_loss__custom_zero_max_loss__reverts() public {
        vm.prank(daddy);
        accountant.addVault(address(vault));

        // Set max loss to 0%
        vm.prank(daddy);
        accountant.setCustomConfig(address(vault), 200, 2_000, 0, 100, 0, 0);

        vm.prank(daddy);
        vault.add_strategy(address(strategy));

        vm.prank(daddy);
        vault.update_max_debt_for_strategy(address(strategy), MAX_INT);

        uint256 amount = 1e18;
        depositIntoVault(vault, user, amount);
        provideStrategyWithDebt(vault, address(strategy), amount);

        assertEq(vault.strategies(address(strategy)).current_debt, amount);

        // Skip time
        skip(31_556_952);

        uint256 gain = 0;
        uint256 loss = 1;

        vm.prank(address(vault));
        vm.expectRevert("too much loss");
        accountant.report(address(strategy), gain, loss);
    }
}
