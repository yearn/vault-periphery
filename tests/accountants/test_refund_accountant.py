import ape
from ape import chain
from utils.constants import ChangeType, ZERO_ADDRESS, MAX_BPS, MAX_INT


def test_setup(daddy, vault, strategy, refund_accountant, fee_recipient):
    accountant = refund_accountant
    assert accountant.feeManager() == daddy
    assert accountant.futureFeeManager() == ZERO_ADDRESS
    assert accountant.feeRecipient() == fee_recipient
    assert accountant.defaultConfig().managementFee == 100
    assert accountant.defaultConfig().performanceFee == 1_000
    assert accountant.defaultConfig().refundRatio == 0
    assert accountant.defaultConfig().maxFee == 0
    assert accountant.defaultConfig().maxGain == 10_000
    assert accountant.defaultConfig().maxLoss == 0
    assert accountant.vaults(vault.address) == False
    assert accountant.useCustomConfig(vault.address, strategy.address) == False
    assert accountant.customConfig(vault.address, strategy.address).managementFee == 0
    assert accountant.customConfig(vault.address, strategy.address).performanceFee == 0
    assert accountant.customConfig(vault.address, strategy.address).refundRatio == 0
    assert accountant.customConfig(vault.address, strategy.address).maxFee == 0
    assert accountant.customConfig(vault.address, strategy.address).maxGain == 0
    assert accountant.customConfig(vault.address, strategy.address).maxLoss == 0
    assert accountant.refund(vault.address, strategy.address) == (False, 0)


def test_add_reward_refund(daddy, vault, strategy, refund_accountant):
    accountant = refund_accountant
    assert accountant.refund(vault.address, strategy.address) == (False, 0)

    amount = int(100)

    with ape.reverts("not added"):
        accountant.setRefund(vault, strategy, True, amount, sender=daddy)

    accountant.addVault(vault, sender=daddy)

    with ape.reverts("!active"):
        accountant.setRefund(vault, strategy, True, amount, sender=daddy)

    vault.add_strategy(strategy, sender=daddy)

    tx = accountant.setRefund(vault, strategy, True, amount, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateRefund))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    assert event[0].refund == True
    assert event[0].amount == amount
    assert accountant.refund(vault.address, strategy.address) == (True, 100)

    with ape.reverts("no refund and non zero amount"):
        accountant.setRefund(vault, strategy, False, amount, sender=daddy)

    tx = accountant.setRefund(vault, strategy, False, 0, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateRefund))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    assert event[0].refund == False
    assert event[0].amount == 0
    assert accountant.refund(vault.address, strategy.address) == (False, 0)


def test_reward_refund(
    daddy, vault, strategy, refund_accountant, user, asset, deposit_into_vault
):
    accountant = refund_accountant
    assert accountant.refund(vault.address, strategy.address) == (False, 0)

    amount = int(100)
    accountant.addVault(vault, sender=daddy)
    vault.add_strategy(strategy, sender=daddy)

    tx = accountant.setRefund(vault, strategy, True, amount, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateRefund))
    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    assert event[0].refund == True
    assert event[0].amount == amount
    assert accountant.refund(vault.address, strategy.address) == (True, 100)

    vault.set_accountant(accountant, sender=daddy)

    user_balance = asset.balanceOf(user)
    to_deposit = user_balance // 2

    # Deposit into vault
    deposit_into_vault(vault, to_deposit)

    # Fund the accountant for a refund. Over fund to make sure it only sends amount.
    asset.transfer(accountant, user_balance - to_deposit, sender=user)

    assert vault.totalAssets() == to_deposit
    assert vault.totalIdle() == to_deposit
    assert vault.profitUnlockingRate() == 0
    assert vault.fullProfitUnlockDate() == 0

    tx = vault.process_report(strategy, sender=daddy)

    event = list(tx.decode_logs(vault.StrategyReported))[0]

    assert event.strategy == strategy.address
    assert event.total_fees == 0
    assert event.gain == 0
    assert event.loss == 0
    assert event.total_refunds == amount
    assert event.current_debt == 0

    assert vault.totalAssets() == amount + to_deposit
    assert vault.totalIdle() == amount + to_deposit
    assert vault.profitUnlockingRate() > 0
    assert vault.fullProfitUnlockDate() > 0

    # Make sure the amounts got reset.
    assert accountant.refund(vault.address, strategy.address) == (False, 0)
    tx = accountant.report(strategy, 0, 0, sender=vault)
    assert tx.return_value == (0, 0)


def test_reward_refund__with_gain(
    daddy,
    vault,
    strategy,
    refund_accountant,
    user,
    asset,
    deposit_into_vault,
    provide_strategy_with_debt,
):
    accountant = refund_accountant
    # Set performance fee to 10% and 0 management fee
    accountant.updateDefaultConfig(0, 1_000, 0, 10_000, 10_000, 0, sender=daddy)
    assert accountant.refund(vault.address, strategy.address) == (False, 0)

    accountant.addVault(vault, sender=daddy)
    vault.add_strategy(strategy, sender=daddy)

    user_balance = asset.balanceOf(user)
    to_deposit = user_balance // 2

    refund = to_deposit // 10
    gain = to_deposit // 10
    loss = 0

    tx = accountant.setRefund(vault, strategy, True, refund, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateRefund))
    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    assert event[0].refund == True
    assert event[0].amount == refund
    assert accountant.refund(vault.address, strategy.address) == (True, refund)

    vault.set_accountant(accountant, sender=daddy)

    # Deposit into vault
    deposit_into_vault(vault, to_deposit)
    # Give strategy debt.
    provide_strategy_with_debt(daddy, strategy, vault, int(to_deposit))
    # simulate profit.
    asset.transfer(strategy, gain, sender=user)

    # Fund the accountant for a refund. Over fund to make sure it only sends amount.
    asset.transfer(accountant, refund, sender=user)

    assert vault.totalAssets() == to_deposit
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == to_deposit
    assert vault.profitUnlockingRate() == 0
    assert vault.fullProfitUnlockDate() == 0

    tx = vault.process_report(strategy, sender=daddy)

    event = list(tx.decode_logs(vault.StrategyReported))[0]

    assert event.strategy == strategy.address
    assert event.total_fees == gain // 10
    assert event.gain == gain
    assert event.loss == 0
    assert event.total_refunds == refund
    assert event.current_debt == to_deposit + gain

    assert vault.totalAssets() == refund + to_deposit + gain
    assert vault.totalIdle() == refund
    assert vault.profitUnlockingRate() > 0
    assert vault.fullProfitUnlockDate() > 0

    # Make sure the amounts got reset.
    assert accountant.refund(vault.address, strategy.address) == (False, 0)
    tx = accountant.report(strategy, 0, 0, sender=vault)
    assert tx.return_value == (0, 0)


def test_reward_refund__with_loss__and_refund(
    daddy,
    vault,
    strategy,
    refund_accountant,
    user,
    asset,
    deposit_into_vault,
    provide_strategy_with_debt,
):
    accountant = refund_accountant
    # Set refund ratio to 100%
    accountant.updateDefaultConfig(
        0, 1_000, 10_000, 10_000, 10_000, 10_000, sender=daddy
    )
    assert accountant.refund(vault.address, strategy.address) == (False, 0)

    accountant.addVault(vault, sender=daddy)
    vault.add_strategy(strategy, sender=daddy)

    user_balance = asset.balanceOf(user)
    to_deposit = user_balance // 2

    refund = to_deposit // 10
    gain = 0
    loss = to_deposit // 10

    tx = accountant.setRefund(vault, strategy, True, refund, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateRefund))
    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    assert event[0].refund == True
    assert event[0].amount == refund
    assert accountant.refund(vault.address, strategy.address) == (True, refund)

    vault.set_accountant(accountant, sender=daddy)

    # Deposit into vault
    deposit_into_vault(vault, to_deposit)
    # Give strategy debt.
    provide_strategy_with_debt(daddy, strategy, vault, int(to_deposit))
    # simulate loss.
    asset.transfer(user, loss, sender=strategy)

    # Fund the accountant for a refund. Over fund to make sure it only sends amount.
    asset.transfer(accountant, refund + loss, sender=user)

    assert vault.totalAssets() == to_deposit
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == to_deposit
    assert vault.profitUnlockingRate() == 0
    assert vault.fullProfitUnlockDate() == 0

    tx = vault.process_report(strategy, sender=daddy)

    event = list(tx.decode_logs(vault.StrategyReported))[0]

    assert event.strategy == strategy.address
    assert event.total_fees == 0
    assert event.gain == gain
    assert event.loss == loss
    assert event.total_refunds == refund + loss
    assert event.current_debt == to_deposit - loss

    assert vault.totalAssets() == refund + to_deposit
    assert vault.totalIdle() == refund + loss
    assert vault.profitUnlockingRate() > 0
    assert vault.fullProfitUnlockDate() > 0

    # Make sure the amounts got reset.
    assert accountant.refund(vault.address, strategy.address) == (False, 0)
    tx = accountant.report(strategy, 0, 0, sender=vault)
    assert tx.return_value == (0, 0)


def test_add_vault(
    daddy,
    vault,
    strategy,
    refund_accountant,
    amount,
    deposit_into_vault,
    provide_strategy_with_debt,
):
    accountant = refund_accountant
    assert accountant.vaults(vault.address) == False

    new_management = 0
    new_performance = 1_000
    new_refund = 0
    new_max_fee = 0
    new_max_gain = 10_000
    new_max_loss = 0

    tx = accountant.updateDefaultConfig(
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
        sender=daddy,
    )

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    with ape.reverts("vault not added"):
        accountant.report(strategy, 0, 0, sender=vault)

    # set vault in accountant
    tx = accountant.addVault(vault.address, sender=daddy)

    event = list(tx.decode_logs(accountant.VaultChanged))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].change == ChangeType.ADDED
    assert accountant.vaults(vault.address) == True

    # Should work now
    tx = accountant.report(strategy, 1_000, 0, sender=vault)
    fees, refunds = tx.return_value
    assert fees == 100
    assert refunds == 0


def test_remove_vault(
    daddy,
    vault,
    strategy,
    refund_accountant,
    amount,
    deposit_into_vault,
    provide_strategy_with_debt,
):
    accountant = refund_accountant
    assert accountant.vaults(vault.address) == False

    new_management = 0
    new_performance = 1_000
    new_refund = 0
    new_max_fee = 0
    new_max_gain = 10_000
    new_max_loss = 0

    tx = accountant.updateDefaultConfig(
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
        sender=daddy,
    )

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert accountant.vaults(vault.address) == False

    # set vault in accountant
    tx = accountant.addVault(vault.address, sender=daddy)

    event = list(tx.decode_logs(accountant.VaultChanged))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].change == ChangeType.ADDED
    assert accountant.vaults(vault.address) == True

    # Should work
    tx = accountant.report(strategy, 1_000, 0, sender=vault)
    fees, refunds = tx.return_value
    assert fees == 100
    assert refunds == 0

    tx = accountant.removeVault(vault.address, sender=daddy)

    event = list(tx.decode_logs(accountant.VaultChanged))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].change == ChangeType.REMOVED
    assert accountant.vaults(vault.address) == False

    # Should now not be able to report.
    with ape.reverts("vault not added"):
        accountant.report(strategy, 0, 0, sender=vault)


def test_set_default_config(daddy, vault, strategy, refund_accountant):
    accountant = refund_accountant
    assert accountant.defaultConfig().managementFee == 100
    assert accountant.defaultConfig().performanceFee == 1_000
    assert accountant.defaultConfig().refundRatio == 0
    assert accountant.defaultConfig().maxFee == 0
    assert accountant.defaultConfig().maxGain == 10_000
    assert accountant.defaultConfig().maxLoss == 0

    new_management = 20
    new_performance = 2_000
    new_refund = 13
    new_max_fee = 18
    new_max_gain = 19
    new_max_loss = 27

    tx = accountant.updateDefaultConfig(
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
        sender=daddy,
    )

    event = list(tx.decode_logs(accountant.UpdateDefaultFeeConfig))

    assert len(event) == 1
    config = list(event[0].defaultFeeConfig)
    assert config[0] == new_management
    assert config[1] == new_performance
    assert config[2] == new_refund
    assert config[3] == new_max_fee
    assert config[4] == new_max_gain
    assert config[5] == new_max_loss

    assert accountant.defaultConfig().managementFee == new_management
    assert accountant.defaultConfig().performanceFee == new_performance
    assert accountant.defaultConfig().refundRatio == new_refund
    assert accountant.defaultConfig().maxFee == new_max_fee
    assert accountant.defaultConfig().maxGain == new_max_gain
    assert accountant.defaultConfig().maxLoss == new_max_loss


def test_set_custom_config(daddy, vault, strategy, refund_accountant):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)

    assert accountant.customConfig(vault.address, strategy.address) == (
        0,
        0,
        0,
        0,
        0,
        0,
    )

    new_management = 20
    new_performance = 2_000
    new_refund = 13
    new_max_fee = 18
    new_max_gain = 19
    new_max_loss = 27

    tx = accountant.setCustomConfig(
        vault.address,
        strategy.address,
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
        sender=daddy,
    )

    event = list(tx.decode_logs(accountant.UpdateCustomFeeConfig))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].strategy == strategy.address
    config = list(event[0].custom_config)

    assert config[0] == new_management
    assert config[1] == new_performance
    assert config[2] == new_refund
    assert config[3] == new_max_fee
    assert config[4] == new_max_gain
    assert config[5] == new_max_loss

    assert (
        accountant.customConfig(vault.address, strategy.address)
        != accountant.defaultConfig()
    )
    assert accountant.customConfig(vault.address, strategy.address) == (
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
    )


def test_remove_custom_config(daddy, vault, strategy, refund_accountant):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)

    assert accountant.customConfig(vault.address, strategy.address) == (
        0,
        0,
        0,
        0,
        0,
        0,
    )

    with ape.reverts("No custom fees set"):
        accountant.removeCustomConfig(vault.address, strategy.address, sender=daddy)

    new_management = 20
    new_performance = 2_000
    new_refund = 13
    new_max_fee = 18
    new_max_gain = 19
    new_max_loss = 27

    accountant.setCustomConfig(
        vault.address,
        strategy.address,
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
        sender=daddy,
    )

    assert accountant.useCustomConfig(vault.address, strategy.address) == True
    assert (
        accountant.customConfig(vault.address, strategy.address)
        != accountant.defaultConfig()
    )
    assert accountant.customConfig(vault.address, strategy.address) == (
        new_management,
        new_performance,
        new_refund,
        new_max_fee,
        new_max_gain,
        new_max_loss,
    )

    tx = accountant.removeCustomConfig(vault.address, strategy.address, sender=daddy)

    event = list(tx.decode_logs(accountant.RemovedCustomFeeConfig))

    assert event[0].strategy == strategy.address
    assert event[0].vault == vault.address
    assert len(event) == 1

    assert accountant.customConfig(vault.address, strategy.address) == (
        0,
        0,
        0,
        0,
        0,
        0,
    )


def test_set_fee_manager(refund_accountant, daddy, user):
    accountant = refund_accountant
    assert accountant.feeManager() == daddy
    assert accountant.futureFeeManager() == ZERO_ADDRESS

    with ape.reverts("!fee manager"):
        accountant.setFutureFeeManager(user, sender=user)

    with ape.reverts("not future fee manager"):
        accountant.acceptFeeManager(sender=user)

    with ape.reverts("not future fee manager"):
        accountant.acceptFeeManager(sender=daddy)

    with ape.reverts("ZERO ADDRESS"):
        accountant.setFutureFeeManager(ZERO_ADDRESS, sender=daddy)

    tx = accountant.setFutureFeeManager(user, sender=daddy)

    event = list(tx.decode_logs(accountant.SetFutureFeeManager))

    assert len(event) == 1
    assert event[0].futureFeeManager == user.address

    assert accountant.feeManager() == daddy
    assert accountant.futureFeeManager() == user

    with ape.reverts("not future fee manager"):
        accountant.acceptFeeManager(sender=daddy)

    tx = accountant.acceptFeeManager(sender=user)

    event = list(tx.decode_logs(accountant.NewFeeManager))

    assert len(event) == 1
    assert event[0].feeManager == user.address

    assert accountant.feeManager() == user
    assert accountant.futureFeeManager() == ZERO_ADDRESS


def test_set_fee_recipient(refund_accountant, daddy, user, fee_recipient):
    accountant = refund_accountant
    assert accountant.feeManager() == daddy
    assert accountant.feeRecipient() == fee_recipient

    with ape.reverts("!fee manager"):
        accountant.setFeeRecipient(user, sender=user)

    with ape.reverts("!fee manager"):
        accountant.setFeeRecipient(user, sender=fee_recipient)

    with ape.reverts("ZERO ADDRESS"):
        accountant.setFeeRecipient(ZERO_ADDRESS, sender=daddy)

    tx = accountant.setFeeRecipient(user, sender=daddy)

    event = list(tx.decode_logs(accountant.UpdateFeeRecipient))

    assert len(event) == 1
    assert event[0].oldFeeRecipient == fee_recipient.address
    assert event[0].newFeeRecipient == user.address

    assert accountant.feeRecipient() == user


def test_distribute(
    refund_accountant,
    daddy,
    user,
    vault,
    fee_recipient,
    deposit_into_vault,
    amount,
):
    accountant = refund_accountant
    deposit_into_vault(vault, amount)

    assert vault.balanceOf(user) == amount
    assert vault.balanceOf(accountant.address) == 0
    assert vault.balanceOf(daddy.address) == 0
    assert vault.balanceOf(fee_recipient.address) == 0

    vault.transfer(accountant.address, amount, sender=user)

    assert vault.balanceOf(user) == 0
    assert vault.balanceOf(accountant.address) == amount
    assert vault.balanceOf(daddy.address) == 0
    assert vault.balanceOf(fee_recipient.address) == 0

    with ape.reverts("!fee manager"):
        accountant.distribute(vault.address, sender=user)

    tx = accountant.distribute(vault.address, sender=daddy)

    event = list(tx.decode_logs(accountant.DistributeRewards))

    assert len(event) == 1
    assert event[0].token == vault.address
    assert event[0].rewards == amount

    assert vault.balanceOf(user) == 0
    assert vault.balanceOf(accountant.address) == 0
    assert vault.balanceOf(daddy.address) == 0
    assert vault.balanceOf(fee_recipient.address) == amount


def test_withdraw_underlying(
    refund_accountant, daddy, user, vault, asset, deposit_into_vault, amount
):
    accountant = refund_accountant
    deposit_into_vault(vault, amount)

    assert vault.balanceOf(user) == amount
    assert vault.balanceOf(accountant.address) == 0
    assert asset.balanceOf(accountant.address) == 0

    vault.transfer(accountant.address, amount, sender=user)

    assert vault.balanceOf(user) == 0
    assert vault.balanceOf(accountant.address) == amount
    assert asset.balanceOf(accountant.address) == 0

    with ape.reverts("!fee manager"):
        accountant.withdrawUnderlying(vault.address, amount, sender=user)

    tx = accountant.withdrawUnderlying(vault.address, amount, sender=daddy)

    assert vault.balanceOf(user) == 0
    assert vault.balanceOf(accountant.address) == 0
    assert asset.balanceOf(accountant.address) == amount


def test_report_profit(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    config = list(accountant.defaultConfig())

    accountant.addVault(vault.address, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = amount // 10
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    assert expected_management_fees + expected_performance_fees == fees
    assert refunds == 0


def test_report_no_profit(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    config = list(accountant.defaultConfig())

    accountant.addVault(vault.address, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = 0
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    assert expected_management_fees + expected_performance_fees == fees
    assert refunds == 0


def test_report_max_fee(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    # SEt max fee of 10% of gain
    accountant.updateDefaultConfig(100, 1_000, 0, 100, 10_000, 0, sender=daddy)
    config = list(accountant.defaultConfig())

    accountant.addVault(vault.address, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = amount // 10
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees > fees
    assert fees == gain * config[3] / MAX_BPS
    assert refunds == 0


def test_report_refund(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    # SEt refund ratio to 100%
    accountant.updateDefaultConfig(100, 1_000, 10_000, 0, 10_000, 10_000, sender=daddy)
    config = list(accountant.defaultConfig())

    accountant.addVault(vault.address, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    gain = 0
    loss = amount // 10

    # make sure accountant has the funds
    asset.mint(accountant.address, loss, sender=daddy)

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    expected_refunds = loss * config[2] / MAX_BPS

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees == fees
    assert expected_refunds == refunds
    assert asset.allowance(accountant.address, vault.address) == expected_refunds


def test_report_refund_not_enough_asset(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    # SEt refund ratio to 100%
    accountant.updateDefaultConfig(100, 1_000, 10_000, 0, 10_000, 10_000, sender=daddy)
    config = list(accountant.defaultConfig())

    accountant.addVault(vault.address, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    gain = 0
    loss = amount // 10

    # make sure accountant has the funds
    asset.mint(accountant.address, loss // 2, sender=daddy)

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    expected_refunds = loss // 2

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees == fees
    assert expected_refunds == refunds
    assert asset.allowance(accountant.address, vault.address) == expected_refunds


def test_report_profit__custom_config(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    accountant.setCustomConfig(
        vault.address, strategy.address, 200, 2_000, 0, 0, 10_000, 0, sender=daddy
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = amount // 10
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    assert expected_management_fees + expected_performance_fees == fees


def test_report_no_profit__custom_config(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    accountant.setCustomConfig(
        vault.address, strategy.address, 200, 2_000, 0, 0, 10_000, 0, sender=daddy
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = 0
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Managmeent fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    assert expected_management_fees + expected_performance_fees == fees
    assert refunds == 0


def test_report_max_fee__custom_config(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    # SEt max fee of 10% of gain
    accountant.setCustomConfig(
        vault.address, strategy.address, 200, 2_000, 0, 100, 10_000, 0, sender=daddy
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = amount // 10
    loss = 0

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees > fees
    assert fees == gain * config[3] / MAX_BPS
    assert refunds == 0


def test_report_profit__custom_zero_max_gain__reverts(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    # SEt max gain to 1%
    accountant.setCustomConfig(
        vault.address, strategy.address, 200, 2_000, 0, 100, 1, 0, sender=daddy
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = amount // 10
    loss = 0

    with ape.reverts("too much gain"):
        accountant.report(strategy.address, gain, loss, sender=vault.address)


def test_report_loss__custom_zero_max_loss__reverts(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    # SEt max gain to 0%
    accountant.setCustomConfig(
        vault.address, strategy.address, 200, 2_000, 0, 100, 0, 0, sender=daddy
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    gain = 0
    loss = 1

    with ape.reverts("too much loss"):
        accountant.report(strategy.address, gain, loss, sender=vault.address)


def test_report_refund__custom_config(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    # SEt refund ratio to 100%
    accountant.setCustomConfig(
        vault.address,
        strategy.address,
        200,
        2_000,
        10_000,
        0,
        10_000,
        10_000,
        sender=daddy,
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    gain = 0
    loss = amount // 10

    # make sure accountant has the funds
    asset.mint(accountant.address, loss, sender=daddy)

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    expected_refunds = loss * config[2] / MAX_BPS

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees == fees
    assert expected_refunds == refunds
    assert asset.allowance(accountant.address, vault.address) == expected_refunds


def test_report_refund_not_enough_asset__custom_config(
    refund_accountant,
    daddy,
    vault,
    strategy,
    amount,
    user,
    deposit_into_vault,
    provide_strategy_with_debt,
    asset,
):
    accountant = refund_accountant
    accountant.addVault(vault.address, sender=daddy)
    # SEt refund ratio to 100%
    accountant.setCustomConfig(
        vault.address,
        strategy.address,
        200,
        2_000,
        10_000,
        0,
        10_000,
        10_000,
        sender=daddy,
    )
    config = list(accountant.customConfig(vault.address, strategy.address))

    vault.add_strategy(strategy.address, sender=daddy)
    vault.update_max_debt_for_strategy(strategy.address, MAX_INT, sender=daddy)

    deposit_into_vault(vault, amount)
    provide_strategy_with_debt(daddy, strategy, vault, amount)

    assert vault.strategies(strategy.address).current_debt == amount

    gain = 0
    loss = amount // 10

    # make sure accountant has the funds
    asset.mint(accountant.address, loss // 2, sender=daddy)

    # Skip a year
    chain.pending_timestamp = (
        vault.strategies(strategy.address).last_report + 31_556_952 - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    tx = accountant.report(strategy.address, gain, loss, sender=vault.address)

    fees, refunds = tx.return_value

    # Management fees
    expected_management_fees = amount * config[0] // MAX_BPS
    # Perf fees
    expected_performance_fees = gain * config[1] // MAX_BPS

    expected_refunds = loss // 2

    # The real fees charged should be less than what would be expected
    assert expected_management_fees + expected_performance_fees == fees
    assert expected_refunds == refunds
    assert asset.allowance(accountant.address, vault.address) == expected_refunds
