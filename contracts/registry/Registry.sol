// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Governance} from "@periphery/utils/Governance.sol";

import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {ReleaseRegistry} from "./ReleaseRegistry.sol";

interface IVault {
    function asset() external view returns (address);

    function api_version() external view returns (string memory);
}

interface IStrategy {
    function asset() external view returns (address);

    function apiVersion() external view returns (string memory);
}

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
        uint256 releaseVersion
    );

    event NewEndorsedStrategy(
        address indexed strategy,
        address indexed asset,
        uint256 releaseVersion
    );

    event RemovedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion
    );

    event RemovedStrategy(
        address indexed strategy,
        address indexed asset,
        uint256 releaseVersion
    );

    // Struct stored for every endorsed vault or strategy for
    // off chain use to easily retrieve info.
    struct Info {
        // The token thats being used.
        address asset;
        // The release number corresponding to the release registries version.
        uint256 releaseVersion;
        // Time when the vault was deployed for easier indexing.
        uint256 deploymentTimestamp;
        // String so that management to tag a vault with any info for FE's.
        string tag;
    }

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

    // asset => array of all endorsed strategies.
    mapping(address => address[]) internal _endorsedStrategies;

    // vault/strategy address => Info struct.
    mapping(address => Info) public info;

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
    function numAssets() external view returns (uint256) {
        return assets.length;
    }

    /**
     * @notice Get the full array of tokens being used.
     * @return The full array of underlying tokens being used/.
     */
    function getAssets() external view returns (address[] memory) {
        return assets;
    }

    /**
     * @notice The amount of endorsed vaults for a specific token.
     * @return The amount of endorsed vaults.
     */
    function numEndorsedVaults(address _asset) public view returns (uint256) {
        return _endorsedVaults[_asset].length;
    }

    /**
     * @notice The amount of endorsed strategies for a specific token.
     * @return The amount of endorsed strategies.
     */
    function numEndorsedStrategies(
        address _asset
    ) public view returns (uint256) {
        return _endorsedStrategies[_asset].length;
    }

    /**
     * @notice Get the array of vaults endorsed for an `_asset`.
     * @param _asset The underlying token used by the vaults.
     * @return The endorsed vaults.
     */
    function getEndorsedVaults(
        address _asset
    ) external view returns (address[] memory) {
        return _endorsedVaults[_asset];
    }

    /**
     * @notice Get the array of strategies endorsed for an `_asset`.
     * @param _asset The underlying token used by the strategies.
     * @return The endorsed strategies.
     */
    function getEndorsedStrategies(
        address _asset
    ) external view returns (address[] memory) {
        return _endorsedStrategies[_asset];
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
     * @notice Get all strategies endorsed through this registry.
     * @dev This will return a nested array of all endorsed strategies
     * separated by their underlying asset.
     *
     * This is only meant for off chain viewing and should not be used during any
     * on chain tx's.
     *
     * @return allEndorsedStrategies A nested array containing all strategies.
     */
    function getAllEndorsedStrategies()
        external
        view
        returns (address[][] memory allEndorsedStrategies)
    {
        address[] memory allAssets = assets;
        uint256 length = assets.length;

        allEndorsedStrategies = new address[][](length);
        for (uint256 i; i < length; ++i) {
            allEndorsedStrategies[i] = _endorsedStrategies[allAssets[i]];
        }
    }

    /**
     * @notice
     *    Create a new vault for the given asset using a given release in the
     *     release registry.
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
    ) public onlyGovernance returns (address _vault) {
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
        _registerVault(_vault, _asset, _releaseTarget, block.timestamp);
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
     * @param _deploymentTimestamp The timestamp of when the vault was deployed for FE use.
     */
    function endorseVault(
        address _vault,
        uint256 _releaseDelta,
        uint256 _deploymentTimestamp
    ) public onlyGovernance {
        // Will underflow if no releases created yet, or targeting prior to release history
        uint256 releaseTarget = ReleaseRegistry(releaseRegistry).numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        // Get the API version for the target specified
        string memory apiVersion = IVaultFactory(
            ReleaseRegistry(releaseRegistry).factories(releaseTarget)
        ).api_version();

        require(
            keccak256(bytes(IVault(_vault).api_version())) ==
                keccak256(bytes((apiVersion))),
            "Wrong API Version"
        );

        // Add to the end of the list of vaults for asset
        _registerVault(
            _vault,
            IVault(_vault).asset(),
            releaseTarget,
            _deploymentTimestamp
        );
    }

    /**
     * @notice Endorse an already deployed vault.
     * @dev To be used with default values for `_releaseDelta` and
     * `_deploymentTimestamp`.
     *
     * @param _vault Address of the vault to endorse.
     */
    function endorseVault(address _vault) external {
        endorseVault(_vault, 0, 0);
    }

    function _registerVault(
        address _vault,
        address _asset,
        uint256 _releaseTarget,
        uint256 _deploymentTimestamp
    ) internal {
        // Add to the endorsed vaults array.
        _endorsedVaults[_asset].push(_vault);

        // Set the Info struct for this vault
        info[_vault] = Info({
            asset: _asset,
            releaseVersion: _releaseTarget,
            deploymentTimestamp: _deploymentTimestamp,
            tag: ""
        });

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit NewEndorsedVault(_vault, _asset, _releaseTarget);
    }

    /**
     * @notice
     *    Adds an existing strategy to the list of "endorsed" strategies for that asset.
     * @dev
     *    Throws if caller isn't `owner`.
     *    Throws if no releases are registered yet.
     *    Throws if `strategies`'s api version does not match the release specified.
     *    Emits a `NewEndorsedStrategy` event.
     * @param _strategy The strategy that will be endorsed by the Registry.
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target.
     * @param _deploymentTimestamp The timestamp of when the strategy was deployed for FE use.
     */
    function endorseStrategy(
        address _strategy,
        uint256 _releaseDelta,
        uint256 _deploymentTimestamp
    ) public onlyGovernance {
        // Will underflow if no releases created yet, or targeting prior to release history
        uint256 _releaseTarget = ReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        // Get the API version for this release
        string memory apiVersion = IVaultFactory(
            ReleaseRegistry(releaseRegistry).factories(_releaseTarget)
        ).api_version();

        // Make sure the API versions match
        require(
            keccak256(bytes((IStrategy(_strategy).apiVersion()))) ==
                keccak256(bytes((apiVersion))),
            "Wrong API Version"
        );

        address _asset = IStrategy(_strategy).asset();

        _endorsedStrategies[_asset].push(_strategy);

        info[_strategy] = Info({
            asset: _asset,
            releaseVersion: _releaseTarget,
            deploymentTimestamp: _deploymentTimestamp,
            tag: ""
        });

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit NewEndorsedStrategy(_strategy, _asset, _releaseTarget);
    }

    /**
     * @notice Endorse an already deployed strategy.
     * @dev To be used with default values for `_releaseDelta` and
     * `_deploymentTimestamp`.
     *
     * @param _strategy Address of the strategy to endorse.
     */
    function endorseStrategy(address _strategy) external {
        endorseStrategy(_strategy, 0, 0);
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
    ) external onlyGovernance {
        require(info[_vault].asset != address(0), "!Endorsed");
        info[_vault].tag = _tag;
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
    ) external onlyGovernance {
        require(info[_vault].asset != address(0), "!endorsed");

        // Get the asset the vault is using.
        address asset = IVault(_vault).asset();
        // Get the release version for this specific vault.
        uint256 releaseTarget = ReleaseRegistry(releaseRegistry).releaseTargets(
            IVault(_vault).api_version()
        );

        require(_endorsedVaults[asset][_index] == _vault, "wrong index");

        // Set the last index to the spot we are removing.
        _endorsedVaults[asset][_index] = _endorsedVaults[asset][
            _endorsedVaults[asset].length - 1
        ];

        // Pop the last item off the array.
        _endorsedVaults[asset].pop();

        // Reset the info config.
        delete info[_vault];

        // Emit the event.
        emit RemovedVault(_vault, asset, releaseTarget);
    }

    /**
     * @notice Remove a `_strategy` at a specific `_index`.
     * @dev Can be used as a efficient way to remove a strategy
     * to not have to iterate over the full array.
     *
     * NOTE: This will not remove the asset from the `assets` array
     * if it is no longer in use and will have to be done manually.
     *
     * @param _strategy Address of the strategy to remove.
     * @param _index Index in the `endorsedStrategies` array `_strategy` sits at.
     */
    function removeStrategy(
        address _strategy,
        uint256 _index
    ) external onlyGovernance {
        require(info[_strategy].asset != address(0), "!endorsed");

        // Get the asset the vault is using.
        address asset = IStrategy(_strategy).asset();
        // Get the release version for this specific vault.
        uint256 releaseTarget = ReleaseRegistry(releaseRegistry).releaseTargets(
            IStrategy(_strategy).apiVersion()
        );

        require(_endorsedStrategies[asset][_index] == _strategy, "wrong index");

        // Set the last index to the spot we are removing.
        _endorsedStrategies[asset][_index] = _endorsedStrategies[asset][
            _endorsedStrategies[asset].length - 1
        ];

        // Pop the last item off the array.
        _endorsedStrategies[asset].pop();

        // Reset the info config.
        delete info[_strategy];

        // Emit the event.
        emit RemovedStrategy(_strategy, asset, releaseTarget);
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
    ) external onlyGovernance {
        require(assetIsUsed[_asset], "!in use");
        require(
            _endorsedVaults[_asset].length == 0 &&
                _endorsedStrategies[_asset].length == 0,
            "still in use"
        );

        require(assets[_index] == _asset, "wrong asset");

        // Replace `_asset` with the last index.
        assets[_index] = assets[assets.length - 1];

        // Pop last item off the array.
        assets.pop();

        // No longer used.
        assetIsUsed[_asset] = false;
    }
}
