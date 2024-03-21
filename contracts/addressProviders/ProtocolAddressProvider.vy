# @version 0.3.7

"""
@title Protocol Address Provider
@license GNU AGPLv3
@author yearn.finance
@notice
    Protocol Address provider for the periphery contracts for Yearn V3.
"""
#### EVENTS ####

event UpdatedAddress:
    addressId: indexed(bytes32)
    oldAddress: indexed(address)
    newAddress: indexed(address)

event UpdatePendingGovernance:
    newPendingGovernance: indexed(address)

event UpdateGovernance:
    previousGovernance: indexed(address)
    newGovernance: indexed(address)

#### CONSTANTS ####

# General Periphery Contracts.
ROUTER: constant(bytes32) = keccak256("ROUTER")
APR_ORACLE: constant(bytes32) = keccak256("APR ORACLE")
RELEASE_REGISTRY: constant(bytes32) = keccak256("RELEASE REGISTRY")
BASE_FEE_PROVIDER: constant(bytes32) = keccak256("BASE FEE PROVIDER")
COMMON_REPORT_TRIGGER: constant(bytes32) = keccak256("COMMON REPORT TRIGGER")

# Periphery Factory contracts.
AUCTION_FACTORY: constant(bytes32) = keccak256("AUCTION FACTORY")
SPLITTER_FACTORY: constant(bytes32) = keccak256("SPLITTER FACTORY")
REGISTRY_FACTORY: constant(bytes32) = keccak256("REGISTRY FACTORY")
ACCOUNTANT_FACTORY: constant(bytes32) = keccak256("ACCOUNTANT FACTORY")

name: public(constant(String[34])) = "Yearn V3 Protocol Address Provider"

#### STORAGE ####

# Mapping of the identifier to the current address.
addresses: HashMap[bytes32, address]

# Address that can set or change the fee configs.
governance: public(address)
# Pending governance waiting to be accepted.
pendingGovernance: public(address)

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
def getAddress(address_id: bytes32) -> address:
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
def getRouter() -> address:
    """
    @notice Get the current Yearn 4626 Router.
    @return Current Yearn 4626 Router
    """
    return self._get_address(ROUTER)

@view
@external
def getAprOracle() -> address:
    """
    @notice Get the current APR Oracle.
    @return Current APR Oracle address.
    """
    return self._get_address(APR_ORACLE)

@view
@external
def getReleaseRegistry() -> address:
    """
    @notice Get the current Release Registry.
    @return Current Release Registry address
    """
    return self._get_address(RELEASE_REGISTRY)

@view
@external
def getBaseFeeProvider() -> address:
    """
    @notice Get the current Base Fee Provider.
    @return Current Base Fee Provider address.
    """
    return self._get_address(BASE_FEE_PROVIDER)

@view
@external
def getCommonReportTrigger() -> address:
    """
    @notice Get the current Common Report Trigger.
    @return Current Common Report Trigger address.
    """
    return self._get_address(COMMON_REPORT_TRIGGER)

@view
@external
def getAuctionFactory() -> address:
    """
    @notice Get the current Auction Factory.
    @return Current Auction Factory address.
    """
    return self._get_address(AUCTION_FACTORY)

@view
@external
def getSplitterFactory() -> address:
    """
    @notice Get the current Splitter Factory.
    @return Current Splitter Factory address.
    """
    return self._get_address(SPLITTER_FACTORY)

@view
@external
def getRegistryFactory() -> address:
    """
    @notice Get the current Registry Factory.
    @return Current Registry Factory address.
    """
    return self._get_address(REGISTRY_FACTORY)

@view
@external
def getAccountantFactory() -> address:
    """
    @notice Get the current Accountant Factory.
    @return Current Accountant Factory address.
    """
    return self._get_address(ACCOUNTANT_FACTORY)


########## SETTERS ##########

@external
def setAddress(address_id: bytes32, new_address: address):
    """
    @notice Sets an address to a given id.
    @dev Must be called by the governance.
    @param address_id The id to set.
    @param new_address The address to set to id.
    """
    self._set_address(address_id, new_address)
    
@internal
def _set_address(address_id: bytes32, new_address: address):
    """
    @notice Internal function to transfer the current address
        for an id and emit the corresponding log
    @param address_id The id to set.
    @param new_address The address to set to id.
    """
    assert msg.sender == self.governance, "!governance"
    old_address: address = self.addresses[address_id]
    self.addresses[address_id] = new_address

    log UpdatedAddress(address_id, old_address, new_address)

@external
def setRouter(new_address: address):
    """
    @notice Sets a new address for the Yearn 4626 Router.
    @dev Must be called by the governance.
    @param new_address The new Router.
    """
    self._set_address(ROUTER, new_address)

@external
def setAprOracle(new_address: address):
    """
    @notice Sets a new address for the APR Oracle.
    @dev Must be called by the governance.
    @param new_address The new APR Oracle.
    """
    self._set_address(APR_ORACLE, new_address)

@external
def setReleaseRegistry(new_address: address):
    """
    @notice Sets a new address for the Release Registry.
    @dev Must be called by the governance.
    @param new_address The new Release Registry.
    """
    self._set_address(RELEASE_REGISTRY, new_address)

@external
def setBaseFeeProvider(new_address: address):
    """
    @notice Sets a new address for the Base Fee Provider.
    @dev Must be called by the governance.
    @param new_address The new Base Fee Provider.
    """
    self._set_address(BASE_FEE_PROVIDER, new_address)

@external
def setCommonReportTrigger(new_address: address):
    """
    @notice Sets a new address for the Common Report Trigger.
    @dev Must be called by the governance.
    @param new_address The new Common Report Trigger.
    """
    self._set_address(COMMON_REPORT_TRIGGER, new_address)

@external
def setAuctionFactory(new_address: address):
    """
    @notice Sets a new address for the Auction Factory.
    @dev Must be called by the governance.
    @param new_address The new Auction Factory.
    """
    self._set_address(AUCTION_FACTORY, new_address)

@external
def setSplitterFactory(new_address: address):
    """
    @notice Sets a new address for the Splitter Factory.
    @dev Must be called by the governance.
    @param new_address The new Splitter Factory.
    """
    self._set_address(SPLITTER_FACTORY, new_address)

@external
def setRegistryFactory(new_address: address):
    """
    @notice Sets a new address for the Registry Factory.
    @dev Must be called by the governance.
    @param new_address The new Registry Factory.
    """
    self._set_address(REGISTRY_FACTORY, new_address)

@external
def setAccountantFactory(new_address: address):
    """
    @notice Sets a new address for the Accountant Factory.
    @dev Must be called by the governance.
    @param new_address The new Accountant Factory.
    """
    self._set_address(ACCOUNTANT_FACTORY, new_address)


########## GOVERNANCE ##########

@external
def transferGovernance(new_governance: address):
    """
    @notice Set the governance address
    @param new_governance The new governance address
    """
    assert msg.sender == self.governance, "!governance"
    self.pendingGovernance = new_governance

    log UpdatePendingGovernance(new_governance)

@external
def acceptGovernance():
    """
    @notice Accept the governance address
    """
    assert msg.sender == self.pendingGovernance, "!pending governance"
    old_governance: address = self.governance
    self.governance = msg.sender
    self.pendingGovernance = empty(address)

    log UpdateGovernance(old_governance, msg.sender)