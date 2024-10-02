// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ISplitterFactory {
    function ORIGINAL() external view returns (address);

    function newSplitter(
        string memory name,
        address manager,
        address manager_recipient,
        address splitee,
        uint256 original_split
    ) external returns (address);

    event NewSplitter(
        address indexed splitter,
        address indexed manager,
        address indexed manager_recipient,
        address splitee
    );
}
