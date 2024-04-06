import ape
from ape import chain
from utils.constants import AddressIds, ZERO_ADDRESS, MAX_INT
from utils.helpers import to_bytes32


def test_address_provider_setup(deploy_address_provider, daddy):
    address_provider = deploy_address_provider(daddy)

    assert address_provider.name() == "Yearn V3 Protocol Address Provider"
    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS
    assert address_provider.getRouter() == ZERO_ADDRESS
    assert address_provider.getKeeper() == ZERO_ADDRESS
    assert address_provider.getAprOracle() == ZERO_ADDRESS
    assert address_provider.getReleaseRegistry() == ZERO_ADDRESS
    assert address_provider.getCommonReportTrigger() == ZERO_ADDRESS
    assert address_provider.getAuctionFactory() == ZERO_ADDRESS
    assert address_provider.getSplitterFactory() == ZERO_ADDRESS
    assert address_provider.getRegistryFactory() == ZERO_ADDRESS
    assert address_provider.getAllocatorFactory() == ZERO_ADDRESS
    assert address_provider.getAccountantFactory() == ZERO_ADDRESS
    assert address_provider.getAddress(("random").encode("utf-8")) == ZERO_ADDRESS


def test__set_address(address_provider, daddy, user):
    id = to_bytes32("random")
    address = user

    assert address_provider.getAddress(id) == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setAddress(id, address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS

    tx = address_provider.setAddress(id, address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address


def test__set_router(address_provider, daddy, user):
    id = AddressIds.ROUTER
    address = user.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getRouter() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setRouter(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getRouter() == ZERO_ADDRESS

    tx = address_provider.setRouter(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getRouter() == address


def test__set_keeper(address_provider, daddy, user, keeper):
    id = AddressIds.KEEPER
    address = keeper.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getKeeper() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setKeeper(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getKeeper() == ZERO_ADDRESS

    tx = address_provider.setKeeper(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getKeeper() == address


def test__set_release_registry(address_provider, daddy, user, release_registry):
    id = AddressIds.RELEASE_REGISTRY
    address = release_registry.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getReleaseRegistry() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setReleaseRegistry(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getReleaseRegistry() == ZERO_ADDRESS

    tx = address_provider.setReleaseRegistry(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getReleaseRegistry() == address


def test__set_common_report_trigger(address_provider, daddy, user):
    id = AddressIds.COMMON_REPORT_TRIGGER
    address = user

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getCommonReportTrigger() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setCommonReportTrigger(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getCommonReportTrigger() == ZERO_ADDRESS

    tx = address_provider.setCommonReportTrigger(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getCommonReportTrigger() == address


def test__set_apr_oracle(address_provider, daddy, user):
    id = AddressIds.APR_ORACLE
    address = user

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAprOracle() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setAprOracle(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAprOracle() == ZERO_ADDRESS

    tx = address_provider.setAprOracle(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getAprOracle() == address


def test__set_base_fee_provider(address_provider, daddy, user):
    id = AddressIds.BASE_FEE_PROVIDER
    address = user

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getBaseFeeProvider() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setBaseFeeProvider(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getBaseFeeProvider() == ZERO_ADDRESS

    tx = address_provider.setBaseFeeProvider(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getBaseFeeProvider() == address


def test__set_auction_factory(address_provider, daddy, user, registry_factory):
    id = AddressIds.AUCTION_FACTORY
    address = registry_factory.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAuctionFactory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setAuctionFactory(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAuctionFactory() == ZERO_ADDRESS

    tx = address_provider.setAuctionFactory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getAuctionFactory() == address


def test__set_splitter_factory(address_provider, daddy, user, splitter_factory):
    id = AddressIds.SPLITTER_FACTORY
    address = splitter_factory.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getSplitterFactory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setSplitterFactory(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getSplitterFactory() == ZERO_ADDRESS

    tx = address_provider.setSplitterFactory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getSplitterFactory() == address


def test__set_registry_factory(address_provider, daddy, user, registry_factory):
    id = AddressIds.REGISTRY_FACTORY
    address = registry_factory.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getRegistryFactory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setRegistryFactory(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getRegistryFactory() == ZERO_ADDRESS

    tx = address_provider.setRegistryFactory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getRegistryFactory() == address


def test__set_allocator_factory(address_provider, daddy, user):
    id = AddressIds.ALLOCATOR_FACTORY
    address = user

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAllocatorFactory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setAllocatorFactory(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAllocatorFactory() == ZERO_ADDRESS

    tx = address_provider.setAllocatorFactory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getAllocatorFactory() == address


def test__set_accountant_factory(address_provider, daddy, user, registry_factory):
    id = AddressIds.ACCOUNTANT_FACTORY
    address = registry_factory.address

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAccountantFactory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.setAccountantFactory(address, sender=user)

    assert address_provider.getAddress(id) == ZERO_ADDRESS
    assert address_provider.getAccountantFactory() == ZERO_ADDRESS

    tx = address_provider.setAccountantFactory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].addressId == id
    assert logs[0].oldAddress == ZERO_ADDRESS
    assert logs[0].newAddress == address

    assert address_provider.getAddress(id) == address
    assert address_provider.getAccountantFactory() == address


def test_gov_transfers_ownership(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS

    address_provider.transferGovernance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == management

    address_provider.acceptGovernance(sender=management)

    assert address_provider.governance() == management
    assert address_provider.pendingGovernance() == ZERO_ADDRESS


def test_gov_transfers_ownership_gov_cant_accept(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS

    address_provider.transferGovernance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == management

    with ape.reverts("!pending governance"):
        address_provider.acceptGovernance(sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == management


def test_random_transfers_ownership__fails(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.transferGovernance(management, sender=management)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS


def test_gov_transfers_ownership__can_change_pending(
    address_provider, daddy, user, management
):
    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == ZERO_ADDRESS

    address_provider.transferGovernance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == management

    address_provider.transferGovernance(user, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pendingGovernance() == user

    with ape.reverts("!pending governance"):
        address_provider.acceptGovernance(sender=management)

    address_provider.acceptGovernance(sender=user)

    assert address_provider.governance() == user
    assert address_provider.pendingGovernance() == ZERO_ADDRESS
