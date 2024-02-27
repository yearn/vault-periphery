import pytest
from ape import accounts, project, networks
from utils.constants import MAX_INT, WEEK, ROLES, ZERO_ADDRESS
from web3 import Web3, HTTPProvider
from hexbytes import HexBytes
import os
import time

# we default to local node
w3 = Web3(HTTPProvider(os.getenv("CHAIN_PROVIDER", "http://127.0.0.1:8545")))


@pytest.fixture(scope="session")
def daddy(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def brain(accounts):
    yield accounts[1]


@pytest.fixture(scope="session")
def security(accounts):
    yield accounts[2]


@pytest.fixture(scope="session")
def management(accounts):
    yield accounts[3]


@pytest.fixture(scope="session")
def fee_recipient(accounts):
    return accounts[4]


@pytest.fixture(scope="session")
def user(accounts):
    return accounts[6]


@pytest.fixture(scope="session")
def vault_manager(accounts):
    return accounts[7]


@pytest.fixture(scope="session")
def strategy_manager(accounts):
    yield accounts[8]


@pytest.fixture(scope="session")
def create_token(project, daddy, user, amount):
    def create_token(initialUser=user, initialAmount=amount):
        token = daddy.deploy(project.MockERC20)

        token.mint(initialUser, initialAmount, sender=daddy)

        return token

    yield create_token


@pytest.fixture(scope="session")
def asset(create_token):
    yield create_token()


@pytest.fixture(scope="session")
def amount():
    return int(1_000 * 1e18)


@pytest.fixture(scope="session")
def vault_original(project, daddy):
    vault = daddy.deploy(project.dependencies["yearn-vaults"]["v3.0.2"].VaultV3)
    return vault.address


@pytest.fixture(scope="session")
def vault_factory(project, daddy, vault_original):
    vault_factory = daddy.deploy(
        project.dependencies["yearn-vaults"]["v3.0.2"].VaultFactory,
        "Vault V3 Factory",
        vault_original,
        daddy.address,
    )
    return vault_factory


@pytest.fixture(scope="session")
def release_registry(project, daddy):
    release_registry = daddy.deploy(project.ReleaseRegistry, daddy)

    yield release_registry


@pytest.fixture(scope="session")
def new_registry(daddy, registry_factory):
    def new_registry(gov=daddy):
        tx = registry_factory.createNewRegistry("New test Registry", gov, sender=gov)
        return project.Registry.at(
            list(tx.decode_logs(registry_factory.NewRegistry))[0].newRegistry
        )

    yield new_registry


@pytest.fixture(scope="session")
def registry_factory(daddy, project, release_registry):
    factory = daddy.deploy(project.RegistryFactory, release_registry)
    yield factory


@pytest.fixture(scope="session")
def registry(new_registry, daddy):
    return new_registry(daddy)


@pytest.fixture(scope="session")
def create_vault(project, daddy, vault_factory):
    def create_vault(
        asset,
        governance=daddy,
        deposit_limit=MAX_INT,
        max_profit_locking_time=WEEK,
        vault_name=None,
        vault_symbol="VV3",
    ):
        vault_suffix = str(int(time.time()))[-4:]
        vault_name = f"Vault V3 {vault_suffix}"

        tx = vault_factory.deploy_new_vault(
            asset,
            vault_name,
            vault_symbol,
            governance,
            max_profit_locking_time,
            sender=daddy,
        )

        event = list(tx.decode_logs(vault_factory.NewVault))
        vault = project.dependencies["yearn-vaults"]["v3.0.2"].VaultV3.at(
            event[0].vault_address
        )

        vault.set_role(
            daddy.address,
            ROLES.ALL,
            sender=daddy,
        )

        # set vault deposit
        vault.set_deposit_limit(deposit_limit, sender=daddy)

        return vault

    yield create_vault


@pytest.fixture(scope="session")
def vault(asset, create_vault):
    vault = create_vault(asset)
    yield vault


@pytest.fixture(scope="session")
def create_strategy(project, management, asset):
    def create_strategy(token=asset, apiVersion="3.0.2"):
        strategy = management.deploy(project.MockStrategy, token.address, apiVersion)

        return strategy

    yield create_strategy


@pytest.fixture(scope="session")
def strategy(asset, create_strategy):
    strategy = create_strategy(asset)
    yield strategy


@pytest.fixture(scope="session")
def deploy_mock_tokenized(project, daddy, vault_factory, asset, management, keeper):
    def deploy_mock_tokenized(name="name", apr=0):
        mock_tokenized = daddy.deploy(
            project.MockTokenized, vault_factory, asset, name, management, keeper, apr
        )
        return mock_tokenized

    yield deploy_mock_tokenized


@pytest.fixture(scope="session")
def mock_tokenized(deploy_mock_tokenized):
    mock_tokenized = deploy_mock_tokenized()

    yield mock_tokenized


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


@pytest.fixture(scope="session")
def deploy_generic_accountant(project, daddy, fee_recipient):
    def deploy_generic_accountant(
        manager=daddy,
        fee_recipient=fee_recipient,
        management_fee=100,
        performance_fee=1_000,
        refund_ratio=0,
        max_fee=0,
    ):
        accountant = daddy.deploy(
            project.GenericAccountant,
            manager,
            fee_recipient,
            management_fee,
            performance_fee,
            refund_ratio,
            max_fee,
        )

        return accountant

    yield deploy_generic_accountant


@pytest.fixture(scope="session")
def deploy_accountant(project, daddy, fee_recipient):
    def deploy_accountant(
        manager=daddy,
        fee_recipient=fee_recipient,
        management_fee=100,
        performance_fee=1_000,
        refund_ratio=0,
        max_fee=0,
        max_gain=10_000,
        max_loss=0,
    ):
        accountant = daddy.deploy(
            project.Accountant,
            manager,
            fee_recipient,
            management_fee,
            performance_fee,
            refund_ratio,
            max_fee,
            max_gain,
            max_loss,
        )

        return accountant

    yield deploy_accountant


@pytest.fixture(scope="session")
def deploy_refund_accountant(project, daddy, fee_recipient):
    def deploy_refund_accountant(
        manager=daddy,
        fee_recipient=fee_recipient,
        management_fee=100,
        performance_fee=1_000,
        refund_ratio=0,
        max_fee=0,
        max_gain=10_000,
        max_loss=0,
    ):
        accountant = daddy.deploy(
            project.RefundAccountant,
            manager,
            fee_recipient,
            management_fee,
            performance_fee,
            refund_ratio,
            max_fee,
            max_gain,
            max_loss,
        )

        return accountant

    yield deploy_refund_accountant


@pytest.fixture(scope="session")
def generic_accountant(deploy_generic_accountant):
    generic_accountant = deploy_generic_accountant()

    yield generic_accountant


@pytest.fixture(scope="session")
def accountant(deploy_accountant):
    accountant = deploy_accountant()

    yield accountant


@pytest.fixture(scope="session")
def refund_accountant(deploy_refund_accountant):
    refund_accountant = deploy_refund_accountant()

    yield refund_accountant


@pytest.fixture(scope="session")
def set_fees_for_strategy():
    def set_fees_for_strategy(
        daddy,
        strategy,
        accountant,
        management_fee,
        performance_fee,
        refund_ratio=0,
        max_fee=0,
    ):
        accountant.set_management_fee(strategy.address, management_fee, sender=daddy)
        accountant.set_performance_fee(strategy.address, performance_fee, sender=daddy)
        accountant.set_refund_ratio(strategy.address, refund_ratio, sender=daddy)
        accountant.set_max_fee(strategy.address, max_fee, sender=daddy)

    return set_fees_for_strategy


@pytest.fixture(scope="session")
def deploy_address_provider(project, daddy):
    def deploy_address_provider(gov=daddy):
        address_provider = gov.deploy(project.AddressProvider, gov)

        return address_provider

    yield deploy_address_provider


@pytest.fixture(scope="session")
def address_provider(deploy_address_provider):
    address_provider = deploy_address_provider()

    yield address_provider


@pytest.fixture(scope="session")
def deploy_debt_allocator_factory(project, daddy, brain):
    def deploy_debt_allocator_factory(gov=daddy):
        debt_allocator_factory = gov.deploy(project.DebtAllocatorFactory, brain)

        return debt_allocator_factory

    yield deploy_debt_allocator_factory


@pytest.fixture(scope="session")
def debt_allocator_factory(deploy_debt_allocator_factory):
    debt_allocator_factory = deploy_debt_allocator_factory()

    yield debt_allocator_factory


@pytest.fixture(scope="session")
def debt_allocator(debt_allocator_factory, project, vault, daddy):
    tx = debt_allocator_factory.newDebtAllocator(vault, sender=daddy)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    debt_allocator = project.DebtAllocator.at(event.allocator)

    yield debt_allocator


@pytest.fixture(scope="session")
def deploy_role_manager(
    project, daddy, brain, security, keeper, strategy_manager, registry
):
    def deploy_role_manager(
        gov=daddy,
        sms=brain,
        sec=security,
        keep=keeper,
        strategy_manage=strategy_manager,
        reg=registry,
    ):
        role_manager = daddy.deploy(
            project.RoleManager, gov, daddy, sms, sec, keep, strategy_manage, reg
        )

        return role_manager

    yield deploy_role_manager


@pytest.fixture(scope="session")
def role_manager(deploy_role_manager, daddy, brain, accountant, debt_allocator_factory):
    role_manager = deploy_role_manager()

    role_manager.setPositionHolder(role_manager.ACCOUNTANT(), accountant, sender=daddy)
    role_manager.setPositionHolder(
        role_manager.ALLOCATOR_FACTORY(), debt_allocator_factory, sender=daddy
    )

    return role_manager


@pytest.fixture(scope="session")
def keeper(daddy):
    yield daddy.deploy(project.Keeper)


@pytest.fixture(scope="session")
def deploy_splitter_factory(project, daddy):
    def deploy_splitter_factory():
        original = daddy.deploy(project.Splitter)

        splitter_factory = daddy.deploy(project.SplitterFactory, original)

        return splitter_factory

    yield deploy_splitter_factory


@pytest.fixture(scope="session")
def splitter_factory(deploy_splitter_factory):
    splitter_factory = deploy_splitter_factory()
    return splitter_factory


@pytest.fixture(scope="session")
def splitter(daddy, management, brain, splitter_factory):
    tx = splitter_factory.newSplitter(
        "Test Splitter", daddy, management, brain, 5_000, sender=daddy
    )
    event = list(tx.decode_logs(splitter_factory.NewSplitter))[0]
    splitter = project.Splitter.at(event.splitter)

    yield splitter
