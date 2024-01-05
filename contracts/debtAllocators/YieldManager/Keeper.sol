// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

/// @notice Holds the `keeper` role of a V3 strategy so that a
///  multiple addresses can call report.
contract Keeper is Governance {
    /// @notice Emitted when a strategy is removed.
    event StrategyRemoved(address indexed strategy);

    /// @notice An event emitted when a keeper is added or removed.
    event UpdateKeeper(address indexed keeper, bool allowed);

    /// @notice Emitted when a new strategy is added to the manager.
    event StrategyAdded(address indexed strategy, address indexed owner);

    /// @notice Only the `_strategy` specific owner can call.
    modifier onlyStrategyOwner(address _strategy) {
        _checkStrategyOwner(_strategy);
        _;
    }

    /// @notice Only the keepers can call.
    modifier onlyKeepers() {
        _checkKeepers();
        _;
    }

    /// @notice Checks if the msg sender is the owner of the strategy.
    function _checkStrategyOwner(address _strategy) internal view virtual {
        require(strategyOwner[_strategy] == msg.sender, "!owner");
    }

    /// @notice Checks if the msg sender is a keeper.
    function _checkKeepers() internal view virtual {
        require(keepers[msg.sender], "!keeper");
    }

    /// @notice Address check for keepers allowed to call.
    mapping(address => bool) public keepers;

    /// @notice strategy address => struct with info.
    mapping(address => address) public strategyOwner;

    constructor(address _governance) Governance(_governance) {}

    /**
     * @notice Add a new strategy, using the current `management` as the owner.
     * @param _strategy The address of the strategy.
     */
    function addNewStrategy(address _strategy) external virtual onlyGovernance {
        require(strategyOwner[_strategy] == address(0), "already active");
        require(IStrategy(_strategy).keeper() == address(this), "!keeper");

        address currentManager = IStrategy(_strategy).management();

        // Store the owner of the strategy.
        strategyOwner[_strategy] = currentManager;

        emit StrategyAdded(_strategy, currentManager);
    }

    /**
     * @notice Updates the owner of a strategy.
     * @param _strategy The address of the strategy.
     * @param _newOwner The address of the new owner.
     */
    function updateStrategyOwner(
        address _strategy,
        address _newOwner
    ) external virtual onlyStrategyOwner(_strategy) {
        require(
            _newOwner != address(0) &&
                _newOwner != address(this) &&
                _newOwner != _strategy,
            "bad address"
        );
        strategyOwner[_strategy] = _newOwner;
    }

    /**
     * @notice Removes the strategy.
     * @param _strategy The address of the strategy.
     */
    function removeStrategy(address _strategy) external virtual {
        // Only governance or the strategy owner can call.
        if (msg.sender != governance) _checkStrategyOwner(_strategy);

        delete strategyOwner[_strategy];

        emit StrategyRemoved(_strategy);
    }

    /**
     * @notice Reports full profit for a strategy.
     * @param _strategy The address of the strategy.
     */
    function report(address _strategy) external virtual onlyKeepers {
        // If the strategy has been added to the keeper.
        if (strategyOwner[_strategy] != address(0)) {
            // Report profits.
            IStrategy(_strategy).report();
        }
    }

    /**
     * @notice Tends a strategy.
     * @param _strategy The address of the strategy.
     */
    function tend(address _strategy) external virtual onlyKeepers {
        // If the strategy has been added to the keeper.
        if (strategyOwner[_strategy] != address(0)) {
            // Tend.
            IStrategy(_strategy).tend();
        }
    }

    /**
     * @notice Set if a keeper can update debt.
     * @param _address The address to set mapping for.
     * @param _allowed If the address can call {update_debt}.
     */
    function setKeeper(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        keepers[_address] = _allowed;

        emit UpdateKeeper(_address, _allowed);
    }
}
