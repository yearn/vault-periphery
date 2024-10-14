// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {ReleaseRegistry} from "./ReleaseRegistry.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance} from "@periphery/utils/Governance.sol";

interface IVaultFactory {
    function deploy_new_vault(
        address asset,
        string memory name,
        string memory symbol,
        address role_manager,
        uint256 profit_max_unlock_time
    ) external returns (address);

    function apiVersion() external view returns (string memory);
}

/**
 * @title YearnV3 Registry
 * @author yearn.finance
 * @notice
 *  Serves as an on chain registry to track any Yearn V3
 *  vaults and strategies that a certain party wants to
 *  endorse.
 *
 *  Can also be used to deploy new vaults of any specific
 *  API version.
 */
contract Registry is Governance {
    /// @notice Emitted when a new vault is deployed or added.
    event NewEndorsedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    /// @notice Emitted when a vault is removed.
    event RemovedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    /// @notice Emitted when a vault is tagged with a string.
    event VaultTagged(address indexed vault);

    /// @notice Emitted when gov adds ore removes a `tagger`.
    event UpdateTagger(address indexed account, bool status);

    /// @notice Emitted when gov adds ore removes a `endorser`.
    event UpdateEndorser(address indexed account, bool status);

    /// @notice Can only be gov or an `endorser`.
    modifier onlyEndorsers() {
        _isEndorser();
        _;
    }

    /// @notice Can only be gov or a `tagger`.
    modifier onlyTaggers() {
        _isTagger();
        _;
    }

    /// @notice Check is gov or an `endorser`.
    function _isEndorser() internal view {
        require(msg.sender == governance || endorsers[msg.sender], "!endorser");
    }

    /// @notice Check is gov or a `tagger`.
    function _isTagger() internal view {
        require(msg.sender == governance || taggers[msg.sender], "!tagger");
    }

    // Struct stored for every endorsed vault or strategy for
    // off chain use to easily retrieve info.
    struct Info {
        // The token thats being used.
        address asset;
        // The release number corresponding to the release registries version.
        uint96 releaseVersion;
        // Type of vault.
        uint64 vaultType;
        // Time when the vault was deployed for easier indexing.
        uint128 deploymentTimestamp;
        // Index the vault is at in array for easy removals.
        uint64 index;
        // String so that management can tag a vault with any info for FE's.
        string tag;
    }

    // Address used to get the specific versions from.
    address public immutable releaseRegistry;

    // Default type used for Multi strategy "Allocator" vaults.
    uint256 public constant MULTI_STRATEGY_TYPE = 1;

    // Default type used for Single "Tokenized" Strategy vaults.
    uint256 public constant SINGLE_STRATEGY_TYPE = 2;

    // Custom name for this Registry.
    string public name;

    // Mapping for any address that is allowed to tag a vault.
    mapping(address => bool) public taggers;

    // Mapping for any address that is allowed to deploy or endorse.
    mapping(address => bool) public endorsers;

    // vault/strategy address => Info struct.
    mapping(address => Info) public vaultInfo;

    // Mapping to check if a specific `asset` has a vault.
    mapping(address => bool) public assetIsUsed;

    // asset => array of all endorsed vaults.
    mapping(address => address[]) internal _endorsedVaults;

    // Array of all tokens used as the underlying.
    address[] public assets;

    /**
     * @param _governance Address to set as owner of the Registry.
     * @param _name The custom string for this custom registry to be called.
     * @param _releaseRegistry The Permissionless releaseRegistry to deploy vaults through.
     */
    constructor(
        address _governance,
        string memory _name,
        address _releaseRegistry
    ) Governance(_governance) {
        // Set name.
        name = _name;
        // Set releaseRegistry.
        releaseRegistry = _releaseRegistry;
    }

    /**
     * @notice Returns the total number of assets being used as the underlying.
     * @return The amount of assets.
     */
    function numAssets() external view virtual returns (uint256) {
        return assets.length;
    }

    /**
     * @notice Get the full array of tokens being used.
     * @return The full array of underlying tokens being used/.
     */
    function getAssets() external view virtual returns (address[] memory) {
        return assets;
    }

    /**
     * @notice The amount of endorsed vaults for a specific token.
     * @return The amount of endorsed vaults.
     */
    function numEndorsedVaults(
        address _asset
    ) public view virtual returns (uint256) {
        return _endorsedVaults[_asset].length;
    }

    /**
     * @notice Get the array of vaults endorsed for an `_asset`.
     * @param _asset The underlying token used by the vaults.
     * @return The endorsed vaults.
     */
    function getEndorsedVaults(
        address _asset
    ) external view virtual returns (address[] memory) {
        return _endorsedVaults[_asset];
    }

    /**
     * @notice Get all endorsed vaults deployed using the Registry.
     * @dev This will return a nested array of all vaults deployed
     * separated by their underlying asset.
     *
     * This is only meant for off chain viewing and should not be used during any
     * on chain tx's.
     *
     * @return allEndorsedVaults A nested array containing all vaults.
     */
    function getAllEndorsedVaults()
        external
        view
        virtual
        returns (address[][] memory allEndorsedVaults)
    {
        address[] memory allAssets = assets;
        uint256 length = assets.length;

        allEndorsedVaults = new address[][](length);
        for (uint256 i; i < length; ++i) {
            allEndorsedVaults[i] = _endorsedVaults[allAssets[i]];
        }
    }

    /**
     * @notice Check if a vault is endorsed in this registry.
     * @dev This will check if the `asset` variable in the struct has been
     *   set for an easy external view check.
     * @param _vault Address of the vault to check.
     * @return . The vaults endorsement status.
     */
    function isEndorsed(address _vault) external view virtual returns (bool) {
        return vaultInfo[_vault].asset != address(0);
    }

    /**
     * @notice
     *    Create and endorse a new multi strategy "Allocator"
     *      vault and endorse it in this registry.
     * @dev
     *   Throws if caller isn't `owner`.
     *   Throws if no releases are registered yet.
     *   Emits a `NewEndorsedVault` event.
     * @param _asset The asset that may be deposited into the new Vault.
     * @param _name Specify a custom Vault name. .
     * @param _symbol Specify a custom Vault symbol name.
     * @param _roleManager The address authorized for guardian interactions in the new Vault.
     * @param _profitMaxUnlockTime The time strategy profits will unlock over.
     * @return _vault address of the newly-deployed vault
     */
    function newEndorsedVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime
    ) public virtual returns (address _vault) {
        return
            newEndorsedVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _profitMaxUnlockTime,
                0 // Default to latest version.
            );
    }

    /**
     * @notice
     *    Create and endorse a new multi strategy "Allocator"
     *      vault and endorse it in this registry.
     * @dev
     *   Throws if caller isn't `owner`.
     *   Throws if no releases are registered yet.
     *   Emits a `NewEndorsedVault` event.
     * @param _asset The asset that may be deposited into the new Vault.
     * @param _name Specify a custom Vault name. .
     * @param _symbol Specify a custom Vault symbol name.
     * @param _roleManager The address authorized for guardian interactions in the new Vault.
     * @param _profitMaxUnlockTime The time strategy profits will unlock over.
     * @param _releaseDelta The number of releases prior to the latest to use as a target. NOTE: Set to 0 for latest.
     * @return _vault address of the newly-deployed vault
     */
    function newEndorsedVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        uint256 _releaseDelta
    ) public virtual onlyEndorsers returns (address _vault) {
        // Get the target release based on the delta given.
        uint256 _releaseTarget = ReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta;

        // Get the factory address for that specific Api version.
        address factory = ReleaseRegistry(releaseRegistry).factories(
            _releaseTarget
        );

        // Make sure we got an actual factory
        require(factory != address(0), "Registry: unknown release");

        // Deploy New vault.
        _vault = IVaultFactory(factory).deploy_new_vault(
            _asset,
            _name,
            _symbol,
            _roleManager,
            _profitMaxUnlockTime
        );

        // Register the vault with this Registry
        _registerVault(
            _vault,
            _asset,
            _releaseTarget,
            MULTI_STRATEGY_TYPE,
            block.timestamp
        );
    }

    /**
     * @notice Endorse an already deployed multi strategy vault.
     * @dev To be used with default values for `_releaseDelta`, `_vaultType`
     * and `_deploymentTimestamp`.

     * @param _vault Address of the vault to endorse.
     */
    function endorseMultiStrategyVault(address _vault) external virtual {
        endorseVault(_vault, 0, MULTI_STRATEGY_TYPE, 0);
    }

    /**
     * @notice Endorse an already deployed Single Strategy vault.
     * @dev To be used with default values for `_releaseDelta`, `_vaultType`
     * and `_deploymentTimestamp`.
     *
     * @param _vault Address of the vault to endorse.
     */
    function endorseSingleStrategyVault(address _vault) external virtual {
        endorseVault(_vault, 0, SINGLE_STRATEGY_TYPE, 0);
    }

    /**
     * @notice
     *    Adds an existing vault to the list of "endorsed" vaults for that asset.
     * @dev
     *    Throws if caller isn't `owner`.
     *    Throws if no releases are registered yet.
     *    Throws if `vault`'s api version does not match the release specified.
     *    Emits a `NewEndorsedVault` event.
     * @param _vault The vault that will be endorsed by the Registry.
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target.
     * @param _vaultType Type of vault to endorse.
     * @param _deploymentTimestamp The timestamp of when the vault was deployed for FE use.
     */
    function endorseVault(
        address _vault,
        uint256 _releaseDelta,
        uint256 _vaultType,
        uint256 _deploymentTimestamp
    ) public virtual onlyEndorsers {
        // Cannot endorse twice.
        require(vaultInfo[_vault].asset == address(0), "endorsed");
        require(_vaultType != 0, "no 0 type");
        require(_vaultType <= type(uint128).max, "type too high");
        require(_deploymentTimestamp <= block.timestamp, "!deployment time");

        // Will underflow if no releases created yet, or targeting prior to release history
        uint256 _releaseTarget = ReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        // Get the API version for the target specified
        string memory apiVersion = IVaultFactory(
            ReleaseRegistry(releaseRegistry).factories(_releaseTarget)
        ).apiVersion();

        require(
            keccak256(bytes(IVault(_vault).apiVersion())) ==
                keccak256(bytes((apiVersion))),
            "Wrong API Version"
        );

        // Add to the end of the list of vaults for asset
        _registerVault(
            _vault,
            IVault(_vault).asset(),
            _releaseTarget,
            _vaultType,
            _deploymentTimestamp
        );
    }

    /**
     * @dev Function used to register a newly deployed or added vault.
     *
     * This well set all of the values for the vault in the `vaultInfo`
     * mapping as well as add the vault and the underlying asset to any
     * relevant arrays for tracking.
     *
     */
    function _registerVault(
        address _vault,
        address _asset,
        uint256 _releaseTarget,
        uint256 _vaultType,
        uint256 _deploymentTimestamp
    ) internal virtual {
        // Set the Info struct for this vault
        vaultInfo[_vault] = Info({
            asset: _asset,
            releaseVersion: uint96(_releaseTarget),
            vaultType: uint64(_vaultType),
            deploymentTimestamp: uint128(_deploymentTimestamp),
            index: uint64(_endorsedVaults[_asset].length),
            tag: ""
        });

        // Add to the endorsed vaults array.
        _endorsedVaults[_asset].push(_vault);

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit NewEndorsedVault(_vault, _asset, _releaseTarget, _vaultType);
    }

    /**
     * @notice Tag a vault with a specific string.
     * @dev This is available to governance to tag any vault or strategy
     * on chain if desired to arbitrarily classify any vaults.
     *   i.e. Certain ratings ("A") / Vault status ("Shutdown") etc.
     *
     * @param _vault Address of the vault or strategy to tag.
     * @param _tag The string to tag the vault or strategy with.
     */
    function tagVault(
        address _vault,
        string memory _tag
    ) external virtual onlyTaggers {
        require(vaultInfo[_vault].asset != address(0), "!Endorsed");
        vaultInfo[_vault].tag = _tag;

        emit VaultTagged(_vault);
    }

    /**
     * @notice Remove a `_vault`.
     * @dev Can be used as an efficient way to remove a vault
     * to not have to iterate over the full array.
     *
     * NOTE: This will not remove the asset from the `assets` array
     * if it is no longer in use and will have to be done manually.
     *
     * @param _vault Address of the vault to remove.
     */
    function removeVault(address _vault) external virtual onlyEndorsers {
        // Get the struct with all the vaults data.
        Info memory info = vaultInfo[_vault];
        require(info.asset != address(0), "!endorsed");
        require(
            _endorsedVaults[info.asset][info.index] == _vault,
            "wrong vault"
        );

        // Get the vault at the end of the array
        address lastVault = _endorsedVaults[info.asset][
            _endorsedVaults[info.asset].length - 1
        ];

        // If `_vault` is not the last item in the array.
        if (lastVault != _vault) {
            // Set the last index to the spot we are removing.
            _endorsedVaults[info.asset][info.index] = lastVault;

            // Update the index of the vault we moved
            vaultInfo[lastVault].index = uint64(info.index);
        }

        // Pop the last item off the array.
        _endorsedVaults[info.asset].pop();

        // Emit the event.
        emit RemovedVault(
            _vault,
            info.asset,
            info.releaseVersion,
            info.vaultType
        );

        // Delete the struct.
        delete vaultInfo[_vault];
    }

    /**
     * @notice Removes a specific `_asset` at `_index` from `assets`.
     * @dev Can be used if an asset is no longer in use after a vault or
     * strategy has also been removed.
     *
     * @param _asset The asset to remove from the array.
     * @param _index The index it sits at.
     */
    function removeAsset(
        address _asset,
        uint256 _index
    ) external virtual onlyEndorsers {
        require(assetIsUsed[_asset], "!in use");
        require(_endorsedVaults[_asset].length == 0, "still in use");
        require(assets[_index] == _asset, "wrong asset");

        // Replace `_asset` with the last index.
        assets[_index] = assets[assets.length - 1];

        // Pop last item off the array.
        assets.pop();

        // No longer used.
        assetIsUsed[_asset] = false;
    }

    /**
     * @notice Set a new address to be able to endorse or remove an existing endorser.
     * @param _account The address to set.
     * @param _canEndorse Bool if the `_account` can or cannot endorse.
     */
    function setEndorser(
        address _account,
        bool _canEndorse
    ) external virtual onlyGovernance {
        endorsers[_account] = _canEndorse;

        emit UpdateEndorser(_account, _canEndorse);
    }

    /**
     * @notice Set a new address to be able to tag a vault.
     * @param _account The address to set.
     * @param _canTag Bool if the `_account` can or cannot tag.
     */
    function setTagger(
        address _account,
        bool _canTag
    ) external virtual onlyGovernance {
        taggers[_account] = _canTag;

        emit UpdateTagger(_account, _canTag);
    }
}
