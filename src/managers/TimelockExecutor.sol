// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Governance} from "@periphery/utils/Governance.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TimelockExecutor is Governance {
    using EnumerableSet for EnumerableSet.AddressSet;

    event ExecutorAdded(address executor);
    event ExecutorRemoved(address executor);

    modifier onlyExecutor() {
        require(isExecutor(msg.sender), "TimelockExecutor: not executor");
        _;
    }

    TimelockController public immutable TIMELOCK;

    EnumerableSet.AddressSet private _executors;

    constructor(
        address _governance,
        address _timelock
    ) Governance(_governance) {
        TIMELOCK = TimelockController(payable(_timelock));
    }

    function execute(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external onlyExecutor {
        TIMELOCK.schedule(target, value, data, predecessor, salt, delay);
    }

    function executeBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external onlyExecutor {
        TIMELOCK.scheduleBatch(targets, values, data, predecessor, salt, delay);
    }

    function isExecutor(address executor) public view returns (bool) {
        return _executors.contains(executor);
    }

    function getExecutors() public view returns (address[] memory) {
        return _executors.values();
    }

    function addExecutor(address executor) external onlyGovernance {
        require(!isExecutor(executor), "TimelockExecutor: already executor");
        _executors.add(executor);
        emit ExecutorAdded(executor);
    }

    function removeExecutor(address executor) external onlyGovernance {
        require(isExecutor(executor), "TimelockExecutor: not executor");
        _executors.remove(executor);
        emit ExecutorRemoved(executor);
    }
}
