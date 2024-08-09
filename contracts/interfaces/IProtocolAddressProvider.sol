// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;


interface IProtocolAddressProvider {
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
}