// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "../ERC20/IERC20.sol";

/**
 * @title RERC20 contract interface, implements {IERC20}. See {RERC20}.
 * @author crypto-pumpkin
 */
interface IRERC20 is IERC20 {
    /// @notice access restriction - owner (R)
    function mint(address _account, uint256 _amount) external returns (bool);
    function burnByRuler(address _account, uint256 _amount) external returns (bool);
}