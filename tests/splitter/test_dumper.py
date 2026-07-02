import ape
from ape import project


def test_dumper(asset, vault, accountant, daddy, brain, amount):
    splitter = daddy
    tf = brain.deploy(project.MockTradeFactory)
    dumper = brain.deploy(
        project.Dumper, brain, accountant.address, splitter, tf, vault
    )
    accountant.setFeeRecipient(dumper, sender=daddy)

    assert dumper.governance() == brain
    assert dumper.accountant() == accountant
    assert dumper.tradeFactory() == tf
    assert dumper.splitToken() == vault
    assert dumper.rewardTokens() == []

    with ape.reverts("!governance"):
        dumper.addTokens([asset], sender=daddy)

    with ape.reverts("!governance"):
        dumper.addToken(asset, sender=daddy)

    dumper.addTokens([asset], sender=brain)

    assert dumper.rewardTokens() == [asset]

    asset.mint(accountant, amount, sender=brain)

    assert asset.balanceOf(accountant) == amount
    assert asset.balanceOf(dumper) == 0
    assert asset.balanceOf(splitter) == 0

    with ape.reverts("!governance"):
        dumper.claim([asset], sender=daddy)

    dumper.claim([asset], sender=brain)

    assert asset.balanceOf(accountant) == 0
    assert asset.balanceOf(dumper) == amount
    assert vault.balanceOf(dumper) == 0
    assert asset.balanceOf(splitter) == 0
    assert vault.balanceOf(splitter) == 0

    asset.transferFrom(dumper, tf, amount, sender=tf)

    assert asset.balanceOf(accountant) == 0
    assert asset.balanceOf(dumper) == 0
    assert asset.balanceOf(tf) == amount

    asset.approve(vault, amount, sender=tf)
    vault.deposit(amount, dumper, sender=tf)

    assert asset.balanceOf(accountant) == 0
    assert asset.balanceOf(dumper) == 0
    assert vault.balanceOf(dumper) == amount
    assert asset.balanceOf(splitter) == 0
    assert vault.balanceOf(splitter) == 0

    dumper.distribute(sender=daddy)

    assert asset.balanceOf(accountant) == 0
    assert asset.balanceOf(dumper) == 0
    assert vault.balanceOf(dumper) == 1
    assert asset.balanceOf(splitter) == 0
    assert vault.balanceOf(splitter) == amount - 1

    with ape.reverts("!governance"):
        dumper.setSplitToken(asset, sender=daddy)

    dumper.setSplitToken(asset, sender=brain)

    assert dumper.governance() == brain
    assert dumper.accountant() == accountant
    assert dumper.tradeFactory() == tf
    assert dumper.splitToken() == asset
    assert dumper.rewardTokens() == [asset]
