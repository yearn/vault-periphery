# @version 0.3.7

from vyper.interfaces import ERC20

# INTERFACES #
struct StrategyParams:
    activation: uint256
    last_report: uint256
    current_debt: uint256
    max_debt: uint256

interface IVault:
    def asset() -> address: view
    def strategies(strategy: address) -> StrategyParams: view

# EVENTS #
event VaultChanged:
    vault: address
    change: VaultChange

event UpdateDefaultFeeConfig:
    default_fee_config: Fee

event SetFutureFeeManager:
    fee_manager: address

event NewFeeManager:
    fee_manager: address

event UpdatePerformanceFee:
    strategy: address
    performance_fee: uint16

event UpdateManagementFee:
    strategy: address
    management_fee: uint16

event UpdateRefundRatio:
    strategy: address
    refund_ratio: uint16

event UpdateMaxFee:
    strategy: address
    max_fee: uint16

event DistributeRewards:
    vault: address
    rewards: uint256

enum VaultChange:
    ADDED
    REMOVED

# STRUCTS #
struct Fee:
    asset: address
    management_fee: uint16
    performance_fee: uint16
    refund_ratio: uint16
    max_fee: uint16


# CONSTANTS #
MAX_BPS: constant(uint256) = 10_000

# NOTE: A four-century period will be missing 3 of its 100 Julian leap years, leaving 97.
#       So the average year has 365 + 97/400 = 365.2425 days
#       ERROR(Julian): -0.0078
#       ERROR(Gregorian): -0.0003
#       A day = 24 * 60 * 60 sec = 86400 sec
#       365.2425 * 86400 = 31556952.0
SECS_PER_YEAR: constant(uint256) = 31_556_952  # 365.2425 days


# STORAGE #
fee_manager: public(address)

future_fee_manager: public(address)
# Mapping of vaults that this serves as an accountant for.
vaults: public(HashMap[address, bool])
# Mapping strategy => Fee config
fees: public(HashMap[address, Fee])
# Default config to use unless a custom one is set.
default_config: public(Fee)

@external
def __init__(
    fee_manager: address, 
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_max: uint16
    ):
    assert default_management <= self._management_fee_threshold(), "exceeds management fee threshold"
    assert default_performance <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    # Set the default fee config
    self.default_config = Fee({
        asset: empty(address),
        management_fee: default_management,
        performance_fee: default_performance,
        refund_ratio: default_refund,
        max_fee: default_max
    })

    log UpdateDefaultFeeConfig(self.default_config)
    
    self.fee_manager = fee_manager

@external
def report(strategy: address, gain: uint256, loss: uint256) -> (uint256, uint256):
    """ """
    assert self.vaults[msg.sender], "!authorized"
    # management_fee is charged in both profit and loss scenarios
    strategy_params: StrategyParams = IVault(msg.sender).strategies(strategy)
    fee: Fee = self.fees[strategy]

    if fee.asset == empty(address):
        # If no custom config is set, use the default
        fee = self.default_config

    total_fees: uint256 = 0
    total_refunds: uint256 = 0

    if fee.management_fee > 0:
        duration: uint256 = block.timestamp - strategy_params.last_report
        #management_fee
        total_fees = (
            strategy_params.current_debt
            * duration
            * convert(fee.management_fee, uint256)
            / MAX_BPS
            / SECS_PER_YEAR
        )

    if gain > 0:
        total_fees += (gain * convert(fee.performance_fee, uint256)) / MAX_BPS

    else:
        if fee.refund_ratio > 0:
            # Give back either all we have or based on refund ratio.
            total_refunds = min(loss * convert(fee.refund_ratio, uint256) / MAX_BPS, ERC20(fee.asset).balanceOf(self))

            if total_refunds > 0:
                # Should not have a refund ratio for random callers.
                self.erc20_safe_approve(fee.asset, msg.sender, total_refunds)
    
    # 0 Max fee means non is enforced.
    if fee.max_fee > 0:
        # ensure fee does not exceed more than 75% of gain
        maximum_fee: uint256 = (gain * convert(fee.max_fee, uint256)) / MAX_BPS

    return (total_fees, total_refunds)

@internal
def erc20_safe_approve(token: address, spender: address, amount: uint256):
    # Used only to send tokens that are not the type managed by this Vault.
    # HACK: Used to handle non-compliant tokens like USDT
    response: Bytes[32] = raw_call(
        token,
        concat(
            method_id("approve(address,uint256)"),
            convert(spender, bytes32),
            convert(amount, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool), "approval failed!"


@external
def add_vault(vault: address):
    """
    @notice Add a new vault for this accountant to charge fee for.
    @dev This is not used to set any of the fees for the specific 
    vault or strategy. Each fee will be set seperatly. 
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.fee_manager, "not fee manager"
    assert not self.vaults[vault], "already added"

    self.vaults[vault] = True

    log VaultChanged(vault, VaultChange.ADDED)


@external
def remove_vault(vault: address):
    """
    @notice Removes a vault for this accountant to charge fee for.
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.fee_manager, "not fee manager"
    assert self.vaults[vault], "not added"

    self.vaults[vault] = False

    log VaultChanged(vault, VaultChange.REMOVED)


@external
def update_default_config(
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_max: uint16
    ):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert default_management <= self._management_fee_threshold(), "exceeds management fee threshold"
    assert default_performance <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    self.default_config = Fee({
        asset: empty(address),
        management_fee: default_management,
        performance_fee: default_performance,
        refund_ratio: default_refund,
        max_fee: default_max
    })

    log UpdateDefaultFeeConfig(self.default_config)

# Should be able to send to a different address.
@external
def distribute(vault: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    rewards: uint256 = ERC20(vault).balanceOf(self)
    ERC20(vault).transfer(msg.sender, rewards)

    log DistributeRewards(vault, rewards)


@external
def set_performance_fee(strategy: address, performance_fee: uint16):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert performance_fee <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    if self.fees[strategy].asset == empty(address):
        self.fees[strategy].asset = IVault(strategy).asset()

    self.fees[strategy].performance_fee = performance_fee

    log UpdatePerformanceFee(strategy, performance_fee)


@external
def set_management_fee(strategy: address, management_fee: uint16):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert management_fee <= self._management_fee_threshold(), "exceeds management fee threshold"
    self.fees[strategy].management_fee = management_fee

    if self.fees[strategy].asset == empty(address):
        self.fees[strategy].asset = IVault(strategy).asset()

    log UpdateManagementFee(strategy, management_fee)


@external
def set_refund_ratio(strategy: address, refund_ratio: uint16):
    assert msg.sender == self.fee_manager, "not fee manager"
    self.fees[strategy].refund_ratio = refund_ratio

    if self.fees[strategy].asset == empty(address):
        self.fees[strategy].asset = IVault(strategy).asset()

    log UpdateRefundRatio(strategy, refund_ratio)


@external
def set_max_fee(strategy: address, max_fee: uint16):
    assert msg.sender == self.fee_manager, "not fee manager"
    self.fees[strategy].max_fee = max_fee

    if self.fees[strategy].asset == empty(address):
        self.fees[strategy].asset = IVault(strategy).asset()

    log UpdateMaxFee(strategy, max_fee)


@external
def set_future_fee_manager(future_fee_manager: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    self.future_fee_manager = future_fee_manager

    log SetFutureFeeManager(future_fee_manager)


@external
def accept_fee_manager():
    assert msg.sender == self.future_fee_manager, "not fee manager"
    self.fee_manager = self.future_fee_manager
    self.future_fee_manager = empty(address)

    log NewFeeManager(self.fee_manager)


@view
@external
def performance_fee_threshold() -> uint16:
    return self._performance_fee_threshold()


@view
@internal
def _performance_fee_threshold() -> uint16:
    return convert(MAX_BPS / 2, uint16)


@view
@external
def management_fee_threshold() -> uint16:
    return self._management_fee_threshold()


@view
@internal
def _management_fee_threshold() -> uint16:
    return 200