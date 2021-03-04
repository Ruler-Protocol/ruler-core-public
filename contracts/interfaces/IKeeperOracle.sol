// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

interface IKeeperOracle {
    function current(address, uint, address) external view returns (uint256);
    function pairFor(address, address) external view returns (address);
    function observationLength(address) external view returns (uint256);
}