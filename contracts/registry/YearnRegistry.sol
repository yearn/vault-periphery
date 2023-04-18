// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRegistry {
    function numReleases() external view returns (uint256);

    function factories(uint256) external view returns (address);

    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        uint256 _releaseDelta
    ) external returns (address);
}

interface IFactory {
    function api_version() external view returns (string memory);
}

interface IVault {
    function asset() external view returns (address);

    function api_version() external view returns (string memory);
}

// TODO: Add strategy stuff
contract Registry is Ownable {
    event EndorsedVault(
        address indexed asset,
        address indexed vault,
        uint256 releaseVersion
    );

    // Address used to deploy the new vaults through
    address public immutable registry;

    // Array of all tokens used as the underlying.
    address[] public assets;

    // Mapping to check it a specific `asset` has a vault.
    mapping(address => bool) public assetIsUsed;

    // asset => array of all endorsed vaults.
    mapping(address => address[]) public endorsedVaults;

    // asset => release number => array of vaults
    mapping(address => mapping(uint256 => address[]))
        public endorsedVaultsByVersion;

    constructor(address _registry) {
        registry = _registry;
    }

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
     * @notice Get the number of endorsed vaults for an asset of a specific API version.
     * @return The amount of endorsed vaults.
     */
    function nuwEndorsedVaultsByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (uint256) {
        uint256 version = IRegistry(registry).numReleases() - 1 - _versionDelta;
        return endorsedVaultsByVersion[_asset][version].length;
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
     * @notice Get the array of vaults endorsed for an `asset` of a specific API.
     * @param _asset The underlying token used by the vaults.
     * @param _versionDelta The difference from the most recent API version.
     * @return The endorsed vaults.
     */
    function getVaultsByVersion(
        address _asset,
        uint256 _versionDelta
    ) public view returns (address[] memory) {
        uint256 version = IRegistry(registry).numReleases() - 1 - _versionDelta;
        return endorsedVaultsByVersion[_asset][version];
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
     * @notice Returns the latest deployed vault for the given asset.
     * @dev Return zero if no vault is associated with the asset
     * @param _asset The asset address to find the latest vault for.
     * @return The address of the latest vault for the given asset.
     */
    function latestEndorsedVault(
        address _asset
    ) external view returns (address) {
        uint256 length = numEndorsedVaults(_asset);

        return endorsedVaults[_asset][length - 1];
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
        vault = IRegistry(registry).newVault(
            _asset,
            _name,
            _symbol,
            _roleManager,
            _profitMaxUnlockTime,
            _releaseDelta
        );

        uint256 releaseTarget = IRegistry(registry).numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        _registerVault(_asset, vault, releaseTarget);
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
     * @param _releaseDelta Specify the number of releases prior to the latest to use as a target. DEFAULT_TYPE is latest.
     */
    function endorseVault(
        address _vault,
        uint256 _releaseDelta
    ) public onlyOwner {
        // NOTE: Underflow if no releases created yet, or targeting prior to release history
        uint256 releaseTarget = IRegistry(registry).numReleases() -
            1 -
            _releaseDelta; // dev: no releases

        string memory apiVersion = IFactory(
            IRegistry(registry).factories(releaseTarget)
        ).api_version();

        require(
            keccak256(bytes((IVault(_vault).api_version()))) ==
                keccak256(bytes((apiVersion)))
        );

        // Add to the end of the list of vaults for asset
        _registerVault(_vault, IVault(_vault).asset(), releaseTarget);
    }

    function endorseVault(address _vault) external {
        endorseVault(_vault, 0);
    }

    function _registerVault(
        address _vault,
        address _asset,
        uint256 _releaseTarget
    ) internal {
        endorsedVaults[_asset].push(_vault);
        endorsedVaultsByVersion[_asset][_releaseTarget].push(_vault);

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }

        emit EndorsedVault(_vault, _asset, _releaseTarget);
    }
}
