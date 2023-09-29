// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVault is IERC4626 {
    struct StrategyParams {
        uint256 activation;
        uint256 last_report;
        uint256 current_debt;
        uint256 max_debt;
    }

    function strategies(
        address _strategy
    ) external view returns (StrategyParams memory);

    function set_role(address, uint256) external;

    function roles(address _address) external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);

    function add_strategy(address) external;

    function update_max_debt_for_strategy(address, uint256) external;

    function update_debt(address, uint256) external;

    function set_deposit_limit(uint256) external;

    function shutdown_vault() external;

    function shutdown() external view returns (bool);

    function minimum_total_idle() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function totalIdle() external view returns (uint256);

    function transfer_role_manager(address role_manager) external;

    function accept_role_manager() external;

    function process_report(address) external;

    function assess_share_of_unrealised_losses(
        address,
        uint256
    ) external view returns (uint256);
}
