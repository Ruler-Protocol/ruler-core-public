// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOracle {
    function getPriceUSD(address _asset) external view returns (uint256 price);
    function getPricesUSD(address[] calldata _assets) external view returns (uint256[] memory prices);
    
    // admin functions
    function updateFeedETH(address _asset, address _feed) external;
    function updateFeedUSD(address _asset, address _feed) external;
    function setSushiKeeperOracle(address _sushiOracle) external;
    function setUniKeeperOracle(address _uniOracle) external;
}