import pytest
from ape import accounts, project
from utils.constants import MAX_INT, WEEK, ROLES
from web3 import Web3, HTTPProvider
from hexbytes import HexBytes
import os

# we default to local node
w3 = Web3(HTTPProvider(os.getenv("CHAIN_PROVIDER", "http://127.0.0.1:8545")))


@pytest.fixture(scope="session")
def daddy(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def management(accounts):
    yield accounts[2]


@pytest.fixture(scope="session")
def user(accounts):
    return accounts[9]


@pytest.fixture(scope="session")
def create_token(project, daddy, user, amount):
    def create_token(
        name="Test Token", symbol="yTest", initialUser=user, initialAmount=amount
    ):
        token = daddy.deploy(
            project.MockERC20,
            name,
            symbol,
            initialUser,
            initialAmount,
        )

        return token

    yield create_token


@pytest.fixture(scope="session")
def asset(create_token):
    yield create_token()


@pytest.fixture(scope="session")
def amount():
    return int(1_000 * 1e18)


@pytest.fixture(scope="session")
def vault_blueprint(project, daddy):
    blueprint_bytecode = b"\xFE\x71\x00" + HexBytes(
        project.dependencies["yearn-vaults"][
            "master"
        ].VaultV3.contract_type.deployment_bytecode.bytecode
    )  # ERC5202
    len_bytes = len(blueprint_bytecode).to_bytes(2, "big")
    deploy_bytecode = HexBytes(
        b"\x61" + len_bytes + b"\x3d\x81\x60\x0a\x3d\x39\xf3" + blueprint_bytecode
    )

    c = w3.eth.contract(abi=[], bytecode=deploy_bytecode)
    deploy_transaction = c.constructor()
    tx_info = {"from": daddy.address, "value": 0, "gasPrice": 0}
    tx_hash = deploy_transaction.transact(tx_info)

    return w3.eth.get_transaction_receipt(tx_hash)["contractAddress"]


@pytest.fixture(scope="session")
def vault_factory(project, daddy, vault_blueprint):
    return daddy.deploy(
        project.dependencies["yearn-vaults"]["master"].VaultFactory,
        "Vault V3 Factory 0.0.1",
        vault_blueprint,
    )


@pytest.fixture(scope="session")
def release_registry(project, daddy):
    release_registry = daddy.deploy(project.ReleaseRegistry)

    yield release_registry


@pytest.fixture(scope="session")
def new_registry(daddy, registry_factory):
    yield project.Registry.at(
        registry_factory.createNewRegistry("New test Registry", sender=daddy)
    )


@pytest.fixture(scope="session")
def registry_factory(daddy, project, release_registry):
    factory = daddy.deploy(project.RegistryFactory, "Test Registry", release_registry)
    yield factory


@pytest.fixture(scope="session")
def registry(registry_factory):
    yield project.Registry.at(registry_factory.original())


@pytest.fixture(scope="session")
def create_vault(project, daddy, vault_factory):
    def create_vault(
        asset,
        governance=daddy,
        deposit_limit=MAX_INT,
        max_profit_locking_time=WEEK,
        vault_name="Test Vault",
        vault_symbol="VV3",
    ):

        tx = vault_factory.deploy_new_vault(
            asset,
            vault_name,
            vault_symbol,
            governance,
            max_profit_locking_time,
            sender=daddy,
        )

        event = list(tx.decode_logs(vault_factory.NewVault))
        vault = project.dependencies["yearn-vaults"]["master"].VaultV3.at(
            event[0].vault_address
        )

        vault.set_role(
            daddy.address,
            ROLES.ADD_STRATEGY_MANAGER
            | ROLES.REVOKE_STRATEGY_MANAGER
            | ROLES.FORCE_REVOKE_MANAGER
            | ROLES.ACCOUNTANT_MANAGER
            | ROLES.QUEUE_MANAGER
            | ROLES.REPORTING_MANAGER
            | ROLES.DEBT_MANAGER
            | ROLES.MAX_DEBT_MANAGER
            | ROLES.DEPOSIT_LIMIT_MANAGER
            | ROLES.MINIMUM_IDLE_MANAGER
            | ROLES.PROFIT_UNLOCK_MANAGER
            | ROLES.SWEEPER
            | ROLES.EMERGENCY_MANAGER,
            sender=daddy,
        )

        # set vault deposit
        vault.set_deposit_limit(deposit_limit, sender=daddy)

        return vault

    yield create_vault


@pytest.fixture(scope="function")
def vault(asset, create_vault):
    vault = create_vault(asset)
    yield vault


@pytest.fixture
def create_strategy(project, management, asset):
    def create_strategy(token=asset, apiVersion="3.1.0"):
        strategy = management.deploy(project.MockStrategy, token.address, apiVersion)

        return strategy

    yield create_strategy


@pytest.fixture(scope="function")
def strategy(asset, create_strategy):
    strategy = create_strategy(asset, "3.1.0")
    yield strategy


@pytest.fixture(scope="function")
def create_vault_and_strategy(strategy, vault, deposit_into_vault):
    def create_vault_and_strategy(account, amount_into_vault):
        deposit_into_vault(vault, amount_into_vault)
        vault.add_strategy(strategy.address, sender=account)
        return vault, strategy

    yield create_vault_and_strategy


@pytest.fixture(scope="function")
def deposit_into_vault(asset, user):
    def deposit_into_vault(vault, amount_to_deposit):
        asset.approve(vault.address, amount_to_deposit, sender=user)
        vault.deposit(amount_to_deposit, user.address, sender=user)

    yield deposit_into_vault


@pytest.fixture(scope="function")
def provide_strategy_with_debt():
    def provide_strategy_with_debt(account, strategy, vault, target_debt: int):
        vault.update_max_debt_for_strategy(
            strategy.address, target_debt, sender=account
        )
        vault.update_debt(strategy.address, target_debt, sender=account)

    return provide_strategy_with_debt
