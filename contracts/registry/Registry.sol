// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IReleaseRegistry {
    function factories(uint256 _releaseTarget) external view returns (address);

    function numReleases() external view returns (uint256);

    function releaseTargets(string memory) external view returns (uint256);
}

interface IStrategy {
    function apiVersion() external view returns (string memory);
}

contract Registry {
    event NewStrategy(
        address indexed strategy,
        address indexed asset,
        string apiVersion
    );

    address public immutable releaseRegistry;

    address[] public assets;
    mapping(address => bool) public assetIsUsed;

    // asset => array of all the vaults
    mapping(address => address[]) public strategies;
    mapping(address => mapping(uint256 => address[]))
        public strategiesByVersion;

    constructor(address _releaseRegistry) {
        releaseRegistry = _releaseRegistry;
    }

    function numassets() external view returns (uint256) {
        return assets.length;
    }

    function numStrategies(address _asset) public view returns (uint256) {
        return strategies[_asset].length;
    }

    function getAssets() external view returns (address[] memory) {
        return assets;
    }

    function getStrategiess(
        address _asset
    ) external view returns (address[] memory) {
        return strategies[_asset];
    }

    function getStrategiessByVersion(
        address _asset,
        uint256 _versionDelta
    ) external view returns (address[] memory) {
        return strategiesByVersion[_asset][_versionDelta];
    }

    /**
     * @notice Get all strategies attached to the Registry.
     * @dev This will return a nested array of all vaults deployed
     * seperated by their underlying asset.
     *
     * This is only meant for off chain viewing and should not be used during any
     * on chain tx's.
     *
     * @return allStrategies A nested array containing all vaults.
     */
    function getAllStrategies()
        external
        view
        returns (address[][] memory allStrategies)
    {
        address[] memory allAssets = assets;
        uint256 length = assets.length;

        allStrategies = new address[][](length);
        for (uint256 i; i < length; ++i) {
            allStrategies[i] = strategies[allAssets[i]];
        }
    }

    function newStrategy(address _strategy, address _asset) external {
        string memory apiVersion = IStrategy(_strategy).apiVersion();

        strategies[_asset].push(_strategy);

        uint256 _releaseTarget = IReleaseRegistry(releaseRegistry)
            .releaseTargets(apiVersion);

        strategiesByVersion[_asset][_releaseTarget].push(_strategy);

        emit NewStrategy(_strategy, _asset, apiVersion);

        if (!assetIsUsed[_asset]) {
            // We have a new asset to add
            assets.push(_asset);
            assetIsUsed[_asset] = true;
        }
    }
}
