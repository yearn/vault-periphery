// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IProtocolAddressProvider {
    event UpdatedAddress(bytes32 id, address oldAddress, address newAddress);

    function name() external view returns (string memory);

    function governance() external view returns (address);

    function pendingGovernance() external view returns (address);

    function transferGovernance(address _newGovernance) external;

    function acceptGovernance() external;

    function setAddress(bytes32 _id, address _address) external;

    function getAddress(bytes32 _id) external view returns (address);

    function setRouter(address _router) external;

    function setKeeper(address _keeper) external;

    function setAprOracle(address _aprOracle) external;

    function setReleaseRegistry(address _releaseRegistry) external;

    function setBaseFeeProvider(address _baseFeeProvider) external;

    function setCommonReportTrigger(address _commonReportTrigger) external;

    function setAuctionFactory(address _auctionFactory) external;

    function setSplitterFactory(address _splitterFactory) external;

    function setRegistryFactory(address _registryFactory) external;

    function setAllocatorFactory(address _allocatorFactory) external;

    function setAccountantFactory(address _accountantFactory) external;

    function setRoleManagerFactory(address _roleManagerFactory) external;

    function getRouter() external view returns (address);

    function getKeeper() external view returns (address);

    function getAprOracle() external view returns (address);

    function getReleaseRegistry() external view returns (address);

    function getBaseFeeProvider() external view returns (address);

    function getCommonReportTrigger() external view returns (address);

    function getAuctionFactory() external view returns (address);

    function getSplitterFactory() external view returns (address);

    function getRegistryFactory() external view returns (address);

    function getAllocatorFactory() external view returns (address);

    function getAccountantFactory() external view returns (address);

    function getRoleManagerFactory() external view returns (address);
}
