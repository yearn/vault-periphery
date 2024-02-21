// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IStrategy {
    function report() external returns (uint256, uint256);

    function tend() external;
}

interface IVault {
    function process_report(address) external returns (uint256, uint256);
}

/**
 * @title Keeper
 * @notice
 *   To allow permissionless reporting on V3 vaults and strategies.
 *
 *   This will do low level calls so that in can be used without reverting
 *   it the roles have not been set or the functions are not available.
 */
contract Keeper {
    /**
     * @notice Reports on a strategy.
     */
    function report(address _strategy) external returns (uint256, uint256) {
        // Call the target with the provided calldata.
        (bool success, bytes memory result) = _strategy.call(
            abi.encodeWithSelector(IStrategy.report.selector)
        );

        if (success) {
            return abi.decode(result, (uint256, uint256));
        }
    }

    /**
     * @notice Tends a strategy.
     */
    function tend(address _strategy) external {
        _strategy.call(abi.encodeWithSelector(IStrategy.tend.selector));
    }

    /**
     * @notice Report strategy profits on a vault.
     */
    function process_report(
        address _vault,
        address _strategy
    ) external returns (uint256, uint256) {
        // Call the target with the provided calldata.
        (bool success, bytes memory result) = _vault.call(
            abi.encodeCall(IVault.process_report, _strategy)
        );

        if (success) {
            return abi.decode(result, (uint256, uint256));
        }
    }
}
