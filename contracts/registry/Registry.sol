// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

// TODO: Add strategy stuff
contract Registry is Ownable {
    event NewVault(address indexed asset, address vault, string apiVersion);

    event NewEndorsedVault(
        address indexed asset,
        address indexed vault,
        string apiVersion
    );

    event NewRelease(
        uint256 indexed releaseId,
        address indexed factory,
        string apiVersion
    );

    // For each new release a new factory will be deployed
    uint256 public numReleases;
    mapping(uint256 => address) public factories;

    address[] public assets;
    mapping(address => bool) public assetIsUsed;

    // asset => array of all the vaults
    mapping(address => address[]) public vaults;
    mapping(address => mapping(uint256 => address[])) public vaultsByVersion;

    function numassets() external view returns (uint256) {
        return assets.length;
    }

    function numVaults(address _asset) public view returns (uint256) {
        return vaults[_asset].length;
    }

    function getAssets() external view returns (address[] memory) {
        return assets;
    }

    function getVaults(
        address _asset
    ) external view returns (address[] memory) {
        return vaults[_asset];
    }

    function getVaultsByVersion(
        address _asset,
        uint256 _versionDelta
    ) external view returns (address[] memory) {
        return vaultsByVersion[_asset][_versionDelta];
    }

    /**
     * @notice Get all vaults deployed using the Registry.
     * @dev This will return a nested array of all vaults deployed
     * seperated by their underlying asset.
     *
     * This is only meant for off chain viewing and should not be used during any
     * on chain tx's.
     *
     * @return allVaults A nested array containing all vaults.
     */
    function getAllVaults()
        external
        view
        returns (address[][] memory allVaults)
    {
        address[] memory allAssets = assets;
        uint256 length = assets.length;

        allVaults = new address[][](length);
        for (uint256 i; i < length; ++i) {
            allVaults[i] = vaults[allAssets[i]];
        }
    }

    function newRelease(address _factory) external onlyOwner {
        // Check if the release is different from the current one
        uint256 releaseId = numReleases;

        if (releaseId > 0) {
            // Make sure this isnt the same as the last one
            require(
                keccak256(
                    bytes(IFactory(factories[releaseId - 1]).api_version())
                ) != keccak256(bytes(IFactory(_factory).api_version())),
                "VaultRegistry: same api version"
            );
        }

        // Update latest release
        factories[releaseId] = _factory;
        numReleases = releaseId + 1;

        // Log the release for external listeners
        emit NewRelease(releaseId, _factory, IFactory(_factory).api_version());
    }

    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime
    ) external returns (address) {
        uint256 _releaseTarget = numReleases - 1;

        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _profitMaxUnlockTime,
                _releaseTarget
            );
    }

    function newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        uint256 _releaseDelta
    ) external returns (address) {
        uint256 _releaseTarget = numReleases - 1 - _releaseDelta;

        return
            _newVault(
                _asset,
                _name,
                _symbol,
                _roleManager,
                _profitMaxUnlockTime,
                _releaseTarget
            );
    }

    function _newVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime,
        uint256 _releaseTarget
    ) internal returns (address vault) {
        address factory = factories[_releaseTarget];
        require(factory != address(0), "VaultRegistry: unknown release");
        string memory apiVersion = IFactory(factory).api_version();

        vault = IFactory(factory).deploy_new_vault(
            ERC20(_asset),
            _name,
            _symbol,
            _roleManager,
            _profitMaxUnlockTime
        );

        emit NewVault(_asset, vault, apiVersion);

        // Add vault and asset to public arrays.
        _registerVault(vault, _asset, _releaseTarget);
    }

    function registerVault(
        address _vault,
        address _asset,
        uint256 _releaseDelta
    ) external {
        uint256 _releaseTarget = numReleases - 1 - _releaseDelta;
        address factory = factories[_releaseTarget];
        require(factory != address(0), "VaultRegistry: unknown release");

        bytes memory vaultCode = _vault.code;
        bytes memory blueprintCode = IFactory(factory).vault_blueprint().code;

        // They should have the exact same code if deployed from the blueprint
        require(
            keccak256(vaultCode) == keccak256(blueprintCode),
            "Not a clone"
        );

        _registerVault(_vault, _asset, _releaseTarget);
    }

    function _registerVault(
        address _vault,
        address _asset,
        uint256 _releaseTarget
    ) internal {
        vaults[_asset].push(_vault);
        vaultsByVersion[_asset][_releaseTarget].push(_vault);

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }
    }
}
