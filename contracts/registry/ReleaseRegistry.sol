// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";

interface IFactory {
    function apiVersion() external view returns (string memory);
}

/**
 * @title YearnV3 Release Registry
 * @author yearn.finance
 * @notice
 *  Used by Yearn Governance to track on chain all
 *  releases of the V3 vaults by API Version.
 */
contract ReleaseRegistry is Governance {
    event NewRelease(
        uint256 indexed releaseId,
        address indexed factory,
        string apiVersion
    );

    string public constant name = "Yearn V3 Release Registry";

    // The total number of releases that have been deployed
    uint256 public numReleases;

    // Mapping of release id starting at 0 to the address
    // of the corresponding factory for that release.
    mapping(uint256 => address) public factories;

    // Mapping of the API version for a specific release to the
    // place in the order it was released.
    mapping(string => uint256) public releaseTargets;

    constructor(address _governance) Governance(_governance) {}

    /**
     * @notice Returns the latest factory.
     * @dev Throws if no releases are registered yet.
     * @return The address of the factory for the latest release.
     */
    function latestFactory() external view returns (address) {
        return factories[numReleases - 1];
    }

    /**
     * @notice Returns the api version of the latest release.
     * @dev Throws if no releases are registered yet.
     * @return The api version of the latest release.
     */
    function latestRelease() external view returns (string memory) {
        return IFactory(factories[numReleases - 1]).apiVersion(); // dev: no release
    }

    /**
     * @notice Issue a new release using a deployed factory.
     * @dev Stores the factory address in `factories` and the release
     * target in `releaseTargets` with its associated API version.
     *
     *   Throws if caller isn't `governance`.
     *   Throws if the api version is the same as the previous release.
     *   Emits a `NewRelease` event.
     *
     * @param _factory The factory that will be used create new vaults.
     */
    function newRelease(address _factory) external onlyGovernance {
        // Check if the release is different from the current one
        uint256 releaseId = numReleases;

        string memory apiVersion = IFactory(_factory).apiVersion();

        if (releaseId > 0) {
            // Make sure this isn't the same as the last one
            require(
                keccak256(
                    bytes(IFactory(factories[releaseId - 1]).apiVersion())
                ) != keccak256(bytes(apiVersion)),
                "ReleaseRegistry: same api version"
            );
        }

        // Update latest release.
        factories[releaseId] = _factory;

        // Set the api to the target.
        releaseTargets[apiVersion] = releaseId;

        // Increase our number of releases.
        numReleases = releaseId + 1;

        // Log the release for external listeners
        emit NewRelease(releaseId, _factory, apiVersion);
    }
}
