// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.18;

interface IVault {
    function roles(address) external view returns (uint256);
}

contract QueueManager {
    address public governance;

    mapping(address => address[]) internal strategies;
    mapping(address => address[]) public queue;

    string public name;

    constructor() {
        name = "Generic Queue Manager";
        governance = msg.sender;
    }

    function get_strategies(
        address vault
    ) external view returns (address[] memory) {
        return strategies[vault];
    }

    function withdraw_queue(
        address vault
    ) external view returns (address[] memory) {
        return queue[vault];
    }

    function new_strategy(address strategy) external {
        strategies[msg.sender].push(strategy);
    }

    function remove_strategy(address strategy) external {
        address[] memory currentStack = strategies[msg.sender];

        for (uint256 i; i < currentStack.length; ++i) {
            address _strategy = currentStack[i];
            if (_strategy == strategy) {
                if (i != currentStack.length - 1) {
                    // if it isn't the last strategy in the stack, move each strategy down one place
                    for (i; i < currentStack.length - 1; ++i) {
                        currentStack[i] = currentStack[i + 1];
                    }
                }

                // store the updated stack
                strategies[msg.sender] = currentStack;
                // pop off the last item
                strategies[msg.sender].pop();

                break;
            }
        }
    }

    function setQueue(address _vault, address[] memory _queue) external {
        uint256 mask = 1 << 4;
        require((IVault(_vault).roles(msg.sender) & mask) == mask, "!gov");
        require(_queue.length <= 10);
        queue[_vault] = _queue;
    }
}
