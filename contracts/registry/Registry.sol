// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Governance} from "@periphery/utils/Governance.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {ReleaseRegistry} from "./ReleaseRegistry.sol";

/**
 * @title YearnV3 Registry
 * @author yearn.finance
 * @notice
 *  Serves as an on chain registry to track any Yearn
 *  vaults and strategies that a certain party wants to
 *  endorse.
 *
 *  Can also be used to deploy new vaults of any specific
 *  API version.
 */
contract Registry is Governance {
    event NewEndorsedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    event RemovedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    // Struct stored for every endorsed vault or strategy for
    // off chain use to easily retrieve info.
    struct Info {
        // The token thats being used.
        address asset;
        // The release number corresponding to the release registries version.
        uint96 releaseVersion;
        // Type of vault.
        uint128 vaultType;
        // Time when the vault was deployed for easier indexing.
        uint128 deploymentTimestamp;
        // String so that management to tag a vault with any info for FE's.
        string tag;
    }

    // Default type used for Multi strategy "Allocator" vaults.
    uint256 public constant MULTI_STRATEGY_TYPE = 1;

    // Default type used for Single "Tokenized" Strategy vaults.
    uint256 public constant SINGLE_STRATEGY_TYPE = 2;

    // Custom name for this Registry.
    string public name;

    // Address used to get the specific versions from.
    address public immutable releaseRegistry;

    // Array of all tokens used as the underlying.
    address[] public assets;

    // Mapping to check if a specific `asset` has a vault.
    mapping(address => bool) public assetIsUsed;

    // asset => array of all endorsed vaults.
    mapping(address => address[]) internal _endorsedVaults;

    // vault/strategy address => Info struct.
    mapping(address => Info) public vaultInfo;

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
    ) public virtual onlyGovernance returns (address _vault) {
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
            ERC20(_asset),
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
    ) public virtual onlyGovernance {
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

    function _registerVault(
        address _vault,
        address _asset,
        uint256 _releaseTarget,
        uint256 _vaultType,
        uint256 _deploymentTimestamp
    ) internal virtual {
        // Add to the endorsed vaults array.
        _endorsedVaults[_asset].push(_vault);

        // Set the Info struct for this vault
        vaultInfo[_vault] = Info({
            asset: _asset,
            releaseVersion: uint96(_releaseTarget),
            vaultType: uint128(_vaultType),
            deploymentTimestamp: uint128(_deploymentTimestamp),
            tag: ""
        });

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
     *   i.e. Certain credit ratings ("AAA") / Vault status ("Shutdown") etc.
     *
     * @param _vault Address of the vault or strategy to tag.
     * @param _tag The string to tag the vault or strategy with.
     */
    function tagVault(
        address _vault,
        string memory _tag
    ) external virtual onlyGovernance {
        require(vaultInfo[_vault].asset != address(0), "!Endorsed");
        vaultInfo[_vault].tag = _tag;
    }

    /**
     * @notice Remove a `_vault` at a specific `_index`.
     * @dev Can be used as an efficient way to remove a vault
     * to not have to iterate over the full array.
     *
     * NOTE: This will not remove the asset from the `assets` array
     * if it is no longer in use and will have to be done manually.
     *
     * @param _vault Address of the vault to remove.
     * @param _index Index in the `endorsedVaults` array `_vault` sits at.
     */
    function removeVault(
        address _vault,
        uint256 _index
    ) external virtual onlyGovernance {
        require(vaultInfo[_vault].asset != address(0), "!endorsed");

        // Get the asset the vault is using.
        address asset = IVault(_vault).asset();
        // Get the release version for this specific vault.
        uint256 releaseTarget = ReleaseRegistry(releaseRegistry).releaseTargets(
            IVault(_vault).apiVersion()
        );

        require(_endorsedVaults[asset][_index] == _vault, "wrong index");

        // Set the last index to the spot we are removing.
        _endorsedVaults[asset][_index] = _endorsedVaults[asset][
            _endorsedVaults[asset].length - 1
        ];

        // Pop the last item off the array.
        _endorsedVaults[asset].pop();

        // Emit the event.
        emit RemovedVault(
            _vault,
            asset,
            releaseTarget,
            vaultInfo[_vault].vaultType
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
    ) external virtual onlyGovernance {
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
}
