import ape
from utils.constants import ChangeType, ZERO_ADDRESS


def test_setup(daddy, vault, strategy, accountant):
    assert accountant.fee_manager() == daddy
    assert accountant.future_fee_manager() == ZERO_ADDRESS
    assert accountant.default_config().management_fee == 100
    assert accountant.default_config().performance_fee == 1_000
    assert accountant.default_config().refund_ratio == 0
    assert accountant.default_config().max_fee == 0
    assert accountant.vaults(vault.address) == False
    assert accountant.custom(strategy.address) == False
    assert accountant.fees(strategy.address).management_fee == 0
    assert accountant.fees(strategy.address).performance_fee == 0
    assert accountant.fees(strategy.address).refund_ratio == 0
    assert accountant.fees(strategy.address).max_fee == 0


def test_add_vault(daddy, vault, strategy, accountant):
    assert accountant.vaults(vault.address) == False

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!authorized"):
        accountant.report(strategy, 0, 0, sender=vault)

    # set vault in accountant
    tx = accountant.add_vault(vault.address, sender=daddy)

    event = list(tx.decode_logs(accountant.VaultChanged))

    assert len(event) == 1
    assert event[0].vault == vault.address
    assert event[0].change == ChangeType.ADDED
    assert accountant.vaults(vault.address) == True

    # Should work now
    accountant.report(strategy, 0, 0, sender=vault)
