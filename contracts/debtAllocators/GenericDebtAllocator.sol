// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "../interfaces/IVault.sol";

contract GenericDebtAllocator is Governance {
    struct Config {
        bool active;
        uint256 targetRatio;
        uint256 minimumChange;
    }

    uint256 internal constant MAX_BPS = 10_000;

    mapping(address => mapping(address => Config)) public configs;

    constructor(address _governance) Governance(_governance) {}

    function shouldUpdateDebt(
        address _vault,
        address _strategy
    ) external view returns (bool, bytes memory) {
        IVault vault = IVault(_vault);
        IVault.StrategyParams memory params = vault.strategies(_strategy);
        require(params.activation != 0, "!activated");

        Config memory config = configs[_vault][_strategy];
        require(config.active, "!active");

        uint256 targetDebt = Math.min(
            (vault.totalAssets() * config.targetRatio) / MAX_BPS,
            params.max_debt
        );

        if (targetDebt > params.current_debt) {
            uint256 toAdd = Math.min(
                targetDebt - params.current_debt,
                vault.totalIdle() - vault.minimum_total_idle()
            );

            uint256 newDebt = Math.min(
                params.current_debt + toAdd,
                params.max_debt
            );

            if (toAdd > config.minimumChange) {
                return (
                    true,
                    abi.encodeWithSelector(
                        vault.update_debt.selector,
                        abi.encode(_strategy, newDebt)
                    )
                );
            }
        } else if (targetDebt < params.current_debt) {
            uint256 toPull = Math.min(
                params.current_debt - targetDebt,
                IVault(_strategy).maxWithdraw(_vault)
            );

            if (toPull > config.minimumChange) {
                return (
                    true,
                    abi.encodeWithSelector(
                        vault.update_debt.selector,
                        abi.encode(_strategy, params.current_debt - toPull)
                    )
                );
            }
        } else {
            return (false, bytes("No Change Needed"));
        }
    }

    function setConfig(
        address _vault,
        address _strategy,
        uint256 _targetRatio,
        uint256 _minChange
    ) external onlyGovernance {
        configs[_vault][_strategy] = Config({
            active: true,
            targetRatio: _targetRatio,
            minimumChange: _minChange
        });
    }

    function removeConfig(
        address _vault,
        address _strategy
    ) external onlyGovernance {
        configs[_vault][_strategy] = Config({
            active: false,
            targetRatio: 0,
            minimumChange: 0
        });
    }
}
