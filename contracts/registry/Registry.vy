# @version 0.3.7

# INTERFACES #
from vyper.interfaces import ERC20

interface IFactory:
    def vault_blueprint()-> address: view
    def deploy_new_vault(
        asset: ERC20,
        name: String[64],
        symbol: String[32],
        role_manager: address,
        profit_max_unlock_time: uint256
    ) -> address: nonpayable

interface IVault:
    def asset() -> address: view
    def apiVersion() -> String[28]: view

event NewRelease:
    release_id: indexed(uint256)
    factory: address
    api_version: String[28]

event NewEndorsedVault:
    token: indexed(address)
    vault_id: indexed(uint256)
    vault: address
    api_version: String[28]

event NewVault:
    token: indexed(address)
    deployer: indexed(address)
    vault: address
    api_version: String[28]

event NewGovernance:
    governance: address

# len(releases)
numReleases: public(uint256)
factories: public(HashMap[uint256, address])

# Token => len(vaults)
numVaults: public(HashMap[address, uint256])
numEndorsedVaults: public(HashMap[address, uint256])

vaults: public(HashMap[address, HashMap[uint256, address]])
endorsedVaults: public(HashMap[address, HashMap[uint256, address]])

# Index of token added => token address
tokens: public(HashMap[uint256, address])
# len(tokens)
numTokens: public(uint256)
# Inclusion check for token
isRegistered: public(HashMap[address, bool])

# 2-phase commit
governance: public(address)
pending_governance: public(address)

@external
def __init__():
    self.governance = msg.sender


@external
def setGovernance(governance: address):
    """
    @notice Starts the 1st phase of the governance transfer.
    @dev Throws if the caller is not current governance.
    @param governance The next governance address
    """
    assert msg.sender == self.governance  # dev: unauthorized
    self.pending_governance = governance


@external
def acceptGovernance():
    """
    @notice Completes the 2nd phase of the governance transfer.
    @dev
        Throws if the caller is not the pending caller.
        Emits a `NewGovernance` event.
    """
    assert msg.sender == self.pending_governance  # dev: unauthorized
    self.governance = msg.sender
    log NewGovernance(msg.sender)


@view
@external
def latestRelease() -> String[28]:
    """
    @notice Returns the api version of the latest release.
    @dev Throws if no releases are registered yet.
    @return The api version of the latest release.
    """
    # NOTE: Throws if there has not been a release yet
    return IVault(IFactory(self.factories[self.numReleases - 1]).vault_blueprint()).apiVersion()  # dev: no release


@view
@external
def latestEndorsedVault(token: address) -> address:
    """
    @notice Returns the latest deployed vault for the given token.
    @dev Throws if no vaults are endorsed yet for the given token.
    @param token The token address to find the latest vault for.
    @return The address of the latest vault for the given token.
    """
    # NOTE: Throws if there has not been a deployed vault yet for this token
    return self.vaults[token][self.numEndorsedVaults[token] - 1]  # dev: no vault for token


@external
def newRelease(factory: address):
    """
    @notice
        Add a new deployed Factory as the contract for the latest release.
        All future vaults deployed will defualt to the newest version.
    @dev
        Throws if caller isn't `self.governance`.
        Throws if `vault`'s governance isn't `self.governance`.
        Throws if the api version is the same as the previous release.
        Emits a `NewVault` event.
    @param factory The contract that will be used as the factory contract for the next release.
    """
    assert msg.sender == self.governance  # dev: unauthorized

    # Check if the release is different from the current one
    # NOTE: This doesn't check for strict semver-style linearly increasing release versions
    release_id: uint256 = self.numReleases  # Next id in series
    if release_id > 0:
        assert (
            IVault(IFactory(self.factories[self.numReleases - 1]).vault_blueprint()).apiVersion()
            != IVault(IFactory(factory).vault_blueprint()).apiVersion()
        )  # dev: same api version
    # else: we are adding the first release to the Registry!

    # Update latest release
    self.factories[release_id] = factory
    self.numReleases = release_id + 1

    # Log the release for external listeners
    log NewRelease(release_id, factory, IVault(IFactory(factory).vault_blueprint()).apiVersion())


@internal
def _newVault(
    asset: ERC20,
    name: String[64],
    symbol: String[32],
    role_manager: address,
    profit_max_unlock_time: uint256,
    releaseTarget: uint256,
) -> address:
    factory: address = self.factories[releaseTarget]
    assert factory != ZERO_ADDRESS  # dev: unknown release
    vault: address = IFactory(factory).deploy_new_vault(asset, name, symbol, role_manager, profit_max_unlock_time)

    return vault


@internal
def _registerVault(token: address, vault: address):
    # Check if there is an existing deployment for this token at the particular api version
    # NOTE: This doesn't check for strict semver-style linearly increasing release versions
    vault_id: uint256 = self.numEndorsedVaults[token]  # Next id in series
    if vault_id > 0:
        assert (
            IVault(self.vaults[token][vault_id - 1]).apiVersion()
            != IVault(vault).apiVersion()
        )  # dev: same api version
    # else: we are adding a new token to the Registry

    # Update the latest deployment
    self.vaults[token][vault_id] = vault
    self.numVaults[token] = vault_id + 1

    # Register tokens for endorsed vaults
    if not self.isRegistered[token]:
        self.isRegistered[token] = True
        self.tokens[self.numTokens] = token
        self.numTokens += 1

    # Log the deployment for external listeners (e.g. Graph)
    log NewEndorsedVault(token, vault_id, vault, IVault(vault).apiVersion())


@external
def newEndorsedVault(
    asset: ERC20,
    name: String[64],
    symbol: String[32],
    role_manager: address,
    profit_max_unlock_time: uint256,
    releaseDelta: uint256 = 0,  # NOTE: Uses latest by default
) -> address:
    """
    @notice
        Create a new vault for the given token using the latest release in the registry,
        as a simple "forwarder-style" delegatecall proxy to the latest release. Also adds
        the new vault to the list of "endorsed" vaults for that token.
    @dev
        `governance` is set in the new vault as `self.governance`, with no ability to override.
        Throws if caller isn't `self.governance`.
        Throws if no releases are registered yet.
        Throws if there already is a registered vault for the given token with the latest api version.
        Emits a `NewVault` event.
    @param asset The token that may be deposited into the new Vault.
    @param name Specify a custom Vault name. Set to empty string for default choice.
    @param symbol Specify a custom Vault symbol name. Set to empty string for default choice.
    @param role_manager The address authorized for guardian interactions in the new Vault.
    @param profit_max_unlock_time The address to use for collecting rewards in the new Vault

    @param releaseDelta Specify the number of releases prior to the latest to use as a target. Default is latest.
    @return The address of the newly-deployed vault
    """
    assert msg.sender == self.governance  # dev: unauthorized

    # NOTE: Underflow if no releases created yet, or targeting prior to release history
    releaseTarget: uint256 = self.numReleases - 1 - releaseDelta  # dev: no releases
    vault: address = self._newVault(asset, name, symbol, role_manager, profit_max_unlock_time, releaseTarget)

    self._registerVault(asset.address, vault)

    return vault


@external
def newVault(
    asset: ERC20,
    name: String[64],
    symbol: String[32],
    role_manager: address,
    profit_max_unlock_time: uint256,
    releaseDelta: uint256 = 0,  # NOTE: Uses latest by default
) -> address:
    """
    @notice
        Create a new vault for the given token using the latest release in the registry,
        as a simple "forwarder-style" delegatecall proxy to the latest release. Does not add
        the new vault to the list of "endorsed" vaults for that token.
    @dev
        Throws if no releases are registered yet.
        Emits a `NewExperimentalVault` event.
    @param asset The token that may be deposited into the new Vault.
    @param name Specify a custom Vault name. Set to empty string for default choice.
    @param symbol Specify a custom Vault symbol name. Set to empty string for default choice.
    @param role_manager The address authorized for guardian interactions in the new Vault.
    @param profit_max_unlock_time The address to use for collecting rewards in the new Vault
    @param releaseDelta Specify the number of releases prior to the latest to use as a target. Default is latest.
    @return The address of the newly-deployed vault
    """
    # NOTE: Underflow if no releases created yet, or targeting prior to release history
    releaseTarget: uint256 = self.numReleases - 1 - releaseDelta  # dev: no releases
    # NOTE: Anyone can call this method, as a convenience to Strategist' experiments
    vault: address = self._newVault(asset, name, symbol, role_manager, profit_max_unlock_time, releaseTarget)

    # NOTE: Not registered, so emit an "experiment" event here instead
    log NewVault(asset.address, msg.sender, vault, IVault(vault).apiVersion())

    return vault


@external
def endorseVault(vault: address, releaseDelta: uint256 = 0):
    """
    @notice
        Adds an existing vault to the list of "endorsed" vaults for that token.
    @dev
        `governance` is set in the new vault as `self.governance`, with no ability to override.
        Throws if caller isn't `self.governance`.
        Throws if `vault`'s governance isn't `self.governance`.
        Throws if no releases are registered yet.
        Throws if `vault`'s api version does not match latest release.
        Throws if there already is a deployment for the vault's token with the latest api version.
        Emits a `NewVault` event.
    @param vault The vault that will be endorsed by the Registry.
    @param releaseDelta Specify the number of releases prior to the latest to use as a target. Default is latest.
    """
    assert msg.sender == self.governance  # dev: unauthorized
    # assert IVault(vault).governance() == msg.sender  # dev: not governed

    # NOTE: Underflow if no releases created yet, or targeting prior to release history
    releaseTarget: uint256 = self.numReleases - 1 - releaseDelta  # dev: no releases
    api_version: String[28] = IVault(IFactory(self.factories[releaseTarget]).vault_blueprint()).apiVersion()
    assert IVault(vault).apiVersion() == api_version  # dev: not target release

    # Add to the end of the list of vaults for token
    self._registerVault(IVault(vault).asset(), vault)

