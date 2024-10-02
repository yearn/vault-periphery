// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ISplitter {
    function initialize(
        string memory _name,
        address _daddy,
        address _management,
        address _brain,
        uint256 _splitterFee
    ) external;

    function name() external view returns (string memory);

    function manager() external view returns (address);

    function managerRecipient() external view returns (address);

    function splitee() external view returns (address);

    function split() external view returns (uint256);

    function maxLoss() external view returns (uint256);

    function auction() external view returns (address);

    function unwrapVault(address vault) external;

    function unwrapVaults(address[] calldata vaults) external;

    function distributeToken(address token) external;

    function distributeTokens(address[] calldata tokens) external;

    function fundAuctions(address[] calldata tokens) external;

    function fundAuction(address token) external;

    function fundAuction(address token, uint256 amount) external;

    function setSplit(uint256 newSplit) external;

    function setMaxLoss(uint256 newMaxLoss) external;

    function setAuction(address newAuction) external;

    function setManager(address newManager) external;

    function setManagerRecipient(address newManagerRecipient) external;

    function setSplitee(address newSplitee) external;

    event UpdatedSplit(uint256 newSplit);
    event UpdatedMaxLoss(uint256 newMaxLoss);
    event UpdatedAuction(address indexed newAuction);
    event UpdatedManagerRecipient(address indexed newManagerRecipient);
    event UpdatedSplitee(address indexed newSplitee);
}
