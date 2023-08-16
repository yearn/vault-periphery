# @version 0.3.7

"""
@title Yearn V3 Address Provider
@license GNU AGPLv3
@author yearn.finance
@notice
    Address provider for the general Yearn V3 contracts.

    Easily retrieve the most recent version of all periphery
    Yearn V3 contracts.

    Based on the Aave Pool Address Provider.
"""
#### EVENTS ####

event UpdatedAddress:
    address_id: indexed(bytes32)
    old_address: indexed(address)
    new_address: indexed(address)

event UpdateGovernance:
    governance: indexed(address)

event NewPendingGovernance:
    pending_governance: indexed(address)

#### CONSTANTS ####

ROUTER: constant(bytes32) = keccak256("ROUTER")
RELEASE_REGISTRY: constant(bytes32) = keccak256("RELEASE REGISTRY")
REGISTRY_FACTORY: constant(bytes32) = keccak256("REGISTRY FACTORY")
COMMON_REPORT_TRIGGER: constant(bytes32) = keccak256("COMMON REPORT TRIGGER")
APR_ORACLE: constant(bytes32) = keccak256("APR ORACLE")

name: public(constant(String[28])) = "Yearn V3 Address Provider"

#### STORAGE ####

# Mapping of the identifier to the current address.
addresses: HashMap[bytes32, address]

# Address that can set or change the fee configs.
governance: public(address)
# Pending governance waiting to be accepted.
pending_governance: public(address)

@external
def __init__(
    governance: address
):
    """
    @notice Deploys the address provider and sets up governance.
    @param governance The address to initially set for governance.
    """
    assert governance != empty(address)
    self.governance = governance

########## GETTERS ##########

@view
@external
def get_address(address_id: bytes32) -> address:
    """
    @notice Returns an address by its identifier..
    @param address_id The id to get the address for.
    @return The address registered for the id.
    """
    return self._get_address(address_id)

@view
@internal
def _get_address(address_id: bytes32) -> address:
    return self.addresses[address_id]

@view
@external
def get_router() -> address:
    """
    @notice Get the current Yearn 4626 Router.
    @return Current Yearn 4626 Router
    """
    return self._get_address(ROUTER)

@view
@external
def get_release_registry() -> address:
    """
    @notice Get the current Release Registry.
    @return Current Release Registry address
    """
    return self._get_address(RELEASE_REGISTRY)

@view
@external
def get_registry_factory() -> address:
    """
    @ Get the current Registry Factory.
    @return Current Registry Factory address.
    """
    return self._get_address(REGISTRY_FACTORY)

@view
@external
def get_common_report_trigger() -> address:
    """
    @ Get the current Common Report Trigger.
    @return Current Common Report Trigger address.
    """
    return self._get_address(COMMON_REPORT_TRIGGER)

@view
@external
def get_apr_oracle() -> address:
    """
    @ Get the current APR Oracle.
    @return Current APR Oracel address.
    """
    return self._get_address(APR_ORACLE)

########## SETTERS ##########

@external
def set_address(address_id: bytes32, new_address: address):
    """
    @notice Sets an address to a given id.
    @dev Must be called by the governance.
    @param address_id The id to set.
    @param new_address The address to set to id.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(address_id, new_address)
    
@internal
def _set_address(address_id: bytes32, new_address: address):
    """
    @notice Internal function to transfer the current address
        for an id and emit the corresponding log
    @param address_id The id to set.
    @param new_address The address to set to id.
    """
    old_address: address = self.addresses[address_id]
    self.addresses[address_id] = new_address

    log UpdatedAddress(address_id, old_address, new_address)

@external
def set_router(new_address: address):
    """
    @notice Sets a new address for the Yearn 4626 Router.
    @dev Must be called by the governance.
    @param new_address The new Router.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(ROUTER, new_address)

@external
def set_release_registry(new_address: address):
    """
    @notice Sets a new address for the Release Registry.
    @dev Must be called by the governance.
    @param new_address The new Release Registry.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(RELEASE_REGISTRY, new_address)

@external
def set_registry_factory(new_address: address):
    """
    @notice Sets a new address for the Release Factory.
    @dev Must be called by the governance.
    @param new_address The new Release Factory.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(REGISTRY_FACTORY, new_address)

@external
def set_common_report_trigger(new_address: address):
    """
    @notice Sets a new address for the Common Report Trigger.
    @dev Must be called by the governance.
    @param new_address The new Common Report Trigger.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(COMMON_REPORT_TRIGGER, new_address)

@external
def set_apr_oracle(new_address: address):
    """
    @notice Sets a new address for the APR Oracle.
    @dev Must be called by the governance.
    @param new_address The new APR Oracle.
    """
    assert msg.sender == self.governance, "!governance"
    self._set_address(APR_ORACLE, new_address)

########## GOVERNANCE ##########

@external
def set_governance(new_governance: address):
    """
    @notice Set the governance address
    @param new_governance The new governance address
    """
    assert msg.sender == self.governance, "!governance"
    self.pending_governance = new_governance

    log NewPendingGovernance(new_governance)

@external
def accept_governance():
    """
    @notice Accept the governance address
    """
    assert msg.sender == self.pending_governance, "!pending governance"
    self.governance = msg.sender
    self.pending_governance = empty(address)

    log UpdateGovernance(msg.sender)