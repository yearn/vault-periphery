// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IReleaseRegistry {
    function numReleases() external view returns (uint256);

    function factories(uint256) external view returns (address);
}

interface IFactory {
    function api_version() external view returns (string memory);

    function vault_blueprint() external view returns (address);

    function deploy_new_vault(
        ERC20 asset,
        string calldata name,
        string calldata symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    ) external returns (address);
}

interface IVault {
    function asset() external view returns (address);

    function api_version() external view returns (string memory);
}

interface IStrategy {
    function asset() external view returns (address);

    function apiVersion() external view returns (string memory);
}

contract CustomRegistry is Ownable {
    event EndorsedVault(
        address indexed asset,
        address indexed vault,
        uint256 releaseVersion
    );

    event EndorsedStrategy(
        address indexed asset,
        address indexed vault,
        uint256 releaseVersion
    );

    struct Info {
        address asset;
        uint256 releaseVersion;
        uint256 deploymentTimeStamp;
    }

    // Custom name for this Registry.
    string public name;

    // Address used to get the specific versions from.
    address public releaseRegistry;

    // Array of all tokens used as the underlying.
    address[] public assets;

    // Mapping to check it a specific `asset` has a vault.
    mapping(address => bool) public assetIsUsed;

    // asset => array of all endorsed vaults.
    mapping(address => address[]) public endorsedVaults;

    // asset => array of all endorsed strategies.
    mapping(address => address[]) public endorsedStrategies;

    // asset => release number => array of endorsed vaults
    mapping(address => mapping(uint256 => address[]))
        public endorsedVaultsByVersion;

    // asset => release number => array of endorsed strategies
    mapping(address => mapping(uint256 => address[]))
        public endorsedStrategiesByVersion;

    // vault/strategy address => Info stuct.
    mapping(address => Info) public info;

    /**
     * @notice Initializes the Custom registry.
     * @dev Should be called atomiclly by the factory after creation.
     *
     * @param _name The custom string for this custom registry to be called.
     * @param _releaseRegistry The Permisionless releaseRegistry to deploy vaults through.
     */
    function initialize(
        string memory _name,
        address _releaseRegistry
    ) external {
        // Can't initialize twice.
        require(releaseRegistry == address(0), "!initialized");

        // Set name.
        name = _name;

        // Set releaseRegistry.
        releaseRegistry = _releaseRegistry;
    }

    /**
     * @notice Returns the total numer of assets being used as the underlying.
     * @return The amount of assets.
     */
    function numassets() external view returns (uint256) {
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
        return endorsedVaults[_asset].length;
    }

    /**
     * @notice The amount of endorsed strategies for a specific token.
     * @return The amount of endorsed strategies.
     */
    function numEndorsedStrategies(
        address _asset
    ) public view returns (uint256) {
        return endorsedStrategies[_asset].length;
    }

    /**
     * @notice Get the number of endorsed vaults for an asset of a specific API version.
     * @return The amount of endorsed vaults.
     */
    function nuwEndorsedVaultsByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (uint256) {
        uint256 version = IReleaseRegistry(releaseRegistry).numReleases() -
            1 -
            _versionDelta;
        return endorsedVaultsByVersion[_asset][version].length;
    }

    /**
     * @notice Get the number of endorsed strategies for an asset of a specific API version.
     * @return The amount of endorsed strategies.
     */
    function nuwEndorsedStrategiesByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (uint256) {
        uint256 version = IReleaseRegistry(releaseRegistry).numReleases() -
            1 -
            _versionDelta;
        return endorsedStrategiesByVersion[_asset][version].length;
    }

    /**
     * @notice Get the full array of vaults that are endorsed for an `asset`.
     * @param _asset The token used as the underlying for the vaults.
     * @return The endorsed vaults.
     */
    function getVaults(
        address _asset
    ) external view returns (address[] memory) {
        return endorsedVaults[_asset];
    }

    /**
     * @notice Get the full array of strategies that are endorsed for an `asset`.
     * @param _asset The token used as the underlying for the strategies.
     * @return The endorsed strategies.
     */
    function getStrategies(
        address _asset
    ) external view returns (address[] memory) {
        return endorsedStrategies[_asset];
    }

    /**
     * @notice Get the array of vaults endorsed for an `asset` of a specific API.
     * @param _asset The underlying token used by the vaults.
     * @param _versionDelta The difference from the most recent API version.
     * @return The endorsed vaults.
     */
    function getVaultsByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (address[] memory) {
        uint256 version = IReleaseRegistry(releaseRegistry).numReleases() -
            1 -
            _versionDelta;
        return endorsedVaultsByVersion[_asset][version];
    }

    /**
     * @notice Get the array of strategies endorsed for an `asset` of a specific API.
     * @param _asset The underlying token used by the strategies.
     * @param _versionDelta The difference from the most recent API version.
     * @return The endorsed strategies.
     */
    function getStrategiesByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (address[] memory) {
        uint256 version = IReleaseRegistry(releaseRegistry).numReleases() -
            1 -
            _versionDelta;
        return endorsedStrategiesByVersion[_asset][version];
    }

    /**
     * @notice Get all endorsed vaults deployed using the Registry.
     * @dev This will return a nested array of all vaults deployed seperated by their
     * underlying asset.
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
            allEndorsedVaults[i] = endorsedVaults[allAssets[i]];
        }
    }

    /**
     * @notice Get all strategies endorsed through this registry.
     * @dev This will return a nested array of all endorsed strategies seperated by their
     * underlying asset.
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
            allEndorsedStrategies[i] = endorsedStrategies[allAssets[i]];
        }
    }

    /**
     * @notice
     *    Create a new vault for the given asset using the latest release in the registry,
     *    as a simple "forwarder-style" delegatecall proxy to the latest release.
     * @dev
     *   `governance` is set in the new vault as `governance`, with no ability to override.
     *   Throws if caller isn't `governance`.
     *   Throws if no releases are registered yet.
     *   Throws if there already is a registered vault for the given asset with the latest api version.
     *   Emits a `NewVault` event.
     * @param _asset The asset that may be deposited into the new Vault.
     * @param _name Specify a custom Vault name. Set to empty string for DEFAULT_TYPE choice.
     * @param _symbol Specify a custom Vault symbol name. Set to empty string for DEFAULT_TYPE choice.
     * @param _roleManager The address authorized for guardian interactions in the new Vault.
     * @param _profitMaxUnlockTime The time
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target. DEFAULT_TYPE is latest.
     * @return vault address of the newly-deployed vault
     */
    function newEndorsedVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        uint256 _releaseDelta
    ) public onlyOwner returns (address vault) {
        // Get the target release based on the delta given.
        uint256 _releaseTarget = IReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta;

        // Get the factory address for that specific Api version.
        address factory = IReleaseRegistry(releaseRegistry).factories(
            _releaseTarget
        );

        // Make sure we got an actual factory
        require(factory != address(0), "Registry: unknown release");

        // Deploy New vault.
        vault = IFactory(factory).deploy_new_vault(
            ERC20(_asset),
            _name,
            _symbol,
            _roleManager,
            _profitMaxUnlockTime
        );

        // Register the vault with this Registry
        _registerVault(vault, _asset, _releaseTarget, block.timestamp);
    }

    /**
     * @notice
     *    Adds an existing vault to the list of "endorsed" vaults for that asset.
     * @dev
     *   Throws if caller isn't `owner`.
     *    Throws if no releases are registered yet.
     *    Throws if `vault`'s api version does not match the release specified.
     *    Emits a `EndorsedVault` event.
     * @param _vault The vault that will be endorsed by the Registry.
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target.
     * @param _deploymentTimestamp The timestamp of when the vault was deployed for FE use.
     */
    function endorseVault(
        address _vault,
        uint256 _releaseDelta,
        uint256 _deploymentTimestamp
    ) public onlyOwner {
        // NOTE: Underflow if no releases created yet, or targeting prior to release history
        uint256 releaseTarget = IReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        string memory apiVersion = IFactory(
            IReleaseRegistry(releaseRegistry).factories(releaseTarget)
        ).api_version();

        require(
            keccak256(bytes((IVault(_vault).api_version()))) ==
                keccak256(bytes((apiVersion)))
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
        endorsedVaults[_asset].push(_vault);
        endorsedVaultsByVersion[_asset][_releaseTarget].push(_vault);

        info[_vault] = Info({
            asset: _asset,
            releaseVersion: _releaseTarget,
            deploymentTimeStamp: _deploymentTimestamp
        });

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit EndorsedVault(_vault, _asset, _releaseTarget);
    }

    /**
     * @notice
     *    Adds an existing strategy to the list of "endorsed" strategies for that asset.
     * @dev
     *   Throws if caller isn't `owner`.
     *    Throws if no releases are registered yet.
     *    Throws if `strategies`'s api version does not match the release specified.
     *    Emits a `EndorsedStrategy` event.
     * @param _strategy The strategy that will be endorsed by the Registry.
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target.
     * @param _deploymentTimestamp The timestamp of when the strategy was deployed for FE use.
     */
    function endorseStrategy(
        address _strategy,
        uint256 _releaseDelta,
        uint256 _deploymentTimestamp
    ) external onlyOwner {
        // NOTE: Underflow if no releases created yet, or targeting prior to release history
        uint256 _releaseTarget = IReleaseRegistry(releaseRegistry)
            .numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        string memory apiVersion = IFactory(
            IReleaseRegistry(releaseRegistry).factories(_releaseTarget)
        ).api_version();

        require(
            keccak256(bytes((IStrategy(_strategy).apiVersion()))) ==
                keccak256(bytes((apiVersion)))
        );

        address _asset = IStrategy(_strategy).asset();

        endorsedStrategies[_asset].push(_strategy);
        endorsedStrategiesByVersion[_asset][_releaseTarget].push(_strategy);

        info[_strategy] = Info({
            asset: _asset,
            releaseVersion: _releaseTarget,
            deploymentTimeStamp: _deploymentTimestamp
        });

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit EndorsedStrategy(_strategy, _asset, _releaseTarget);
    }
}
