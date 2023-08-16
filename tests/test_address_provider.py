import ape
from ape import chain
from utils.constants import AddressIds, ZERO_ADDRESS, MAX_INT
from utils.helpers import to_bytes32


def test_address_provider_setup(deploy_address_provider, daddy):
    address_provider = deploy_address_provider(daddy)

    assert address_provider.name() == "Yearn V3 Address Provider"
    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS
    assert address_provider.get_router() == ZERO_ADDRESS
    assert address_provider.get_release_registry() == ZERO_ADDRESS
    assert address_provider.get_common_report_trigger() == ZERO_ADDRESS
    assert address_provider.get_apr_oracle() == ZERO_ADDRESS
    assert address_provider.get_registry_factory() == ZERO_ADDRESS
    assert address_provider.get_address(("random").encode("utf-8")) == ZERO_ADDRESS


def test__set_address(address_provider, daddy, user):
    id = to_bytes32("random")
    address = user

    assert address_provider.get_address(id) == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_address(id, address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS

    tx = address_provider.set_address(id, address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address


def test__set_router(address_provider, daddy, user):
    id = AddressIds.ROUTER
    address = user.address

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_router() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_router(address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_router() == ZERO_ADDRESS

    tx = address_provider.set_router(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address
    assert address_provider.get_router() == address


def test__set_release_registry(address_provider, daddy, user, release_registry):
    id = AddressIds.RELEASE_REGISTRY
    address = release_registry.address

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_release_registry() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_release_registry(address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_release_registry() == ZERO_ADDRESS

    tx = address_provider.set_release_registry(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address
    assert address_provider.get_release_registry() == address


def test__set_common_report_trigger(address_provider, daddy, user):
    id = AddressIds.COMMON_REPORT_TRIGGER
    address = user

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_common_report_trigger() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_common_report_trigger(address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_common_report_trigger() == ZERO_ADDRESS

    tx = address_provider.set_common_report_trigger(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address
    assert address_provider.get_common_report_trigger() == address


def test__set_apr_oracle(address_provider, daddy, user):
    id = AddressIds.APR_ORACLE
    address = user

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_apr_oracle() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_apr_oracle(address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_apr_oracle() == ZERO_ADDRESS

    tx = address_provider.set_apr_oracle(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address
    assert address_provider.get_apr_oracle() == address


def test__set_registry_factory(address_provider, daddy, user, registry_factory):
    id = AddressIds.REGISTRY_FACTORY
    address = registry_factory.address

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_registry_factory() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_registry_factory(address, sender=user)

    assert address_provider.get_address(id) == ZERO_ADDRESS
    assert address_provider.get_registry_factory() == ZERO_ADDRESS

    tx = address_provider.set_registry_factory(address, sender=daddy)

    logs = list(tx.decode_logs(address_provider.UpdatedAddress))

    assert len(logs) == 1
    assert logs[0].address_id == id
    assert logs[0].old_address == ZERO_ADDRESS
    assert logs[0].new_address == address

    assert address_provider.get_address(id) == address
    assert address_provider.get_registry_factory() == address


def test_gov_transfers_ownership(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS

    address_provider.set_governance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == management

    address_provider.accept_governance(sender=management)

    assert address_provider.governance() == management
    assert address_provider.pending_governance() == ZERO_ADDRESS


def test_gov_transfers_ownership__gov_cant_accept(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS

    address_provider.set_governance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == management

    with ape.reverts("!pending governance"):
        address_provider.accept_governance(sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == management


def test_random_transfers_ownership__fails(address_provider, daddy, management):
    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS

    with ape.reverts("!governance"):
        address_provider.set_governance(management, sender=management)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS


def test_gov_transfers_ownership__can_change_pending(
    address_provider, daddy, user, management
):
    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == ZERO_ADDRESS

    address_provider.set_governance(management, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == management

    address_provider.set_governance(user, sender=daddy)

    assert address_provider.governance() == daddy
    assert address_provider.pending_governance() == user

    with ape.reverts("!pending governance"):
        address_provider.accept_governance(sender=management)

    address_provider.accept_governance(sender=user)

    assert address_provider.governance() == user
    assert address_provider.pending_governance() == ZERO_ADDRESS
