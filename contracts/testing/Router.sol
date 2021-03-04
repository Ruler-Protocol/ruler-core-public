// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC20/ERC20.sol";
import "../ERC20/IERC20.sol";

/// Dummy contract to test Uniswap locally
contract Router {
    IERC20 public paired;
    IERC20 public lpToken;

    constructor (IERC20 _paired, IERC20 _lpToken) {
        paired = _paired;
        lpToken = _lpToken;
    }

    function swapExactTokensForTokens(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline > block.timestamp);
        require(amountOutMin >= 0);
        IERC20 input = IERC20(path[0]);
        input.transferFrom(msg.sender, address(this), amountIn);
        paired.transfer(to, amountIn);
        amounts = new uint256[](1);
        amounts[0] = amountIn;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline > block.timestamp);
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);
        IERC20 token0 = IERC20(tokenA);
        IERC20 token1 = IERC20(tokenB);
        token0.transferFrom(msg.sender, address(this), amountADesired);
        token1.transferFrom(msg.sender, address(this), amountBDesired);
        lpToken.transfer(to, amountADesired);
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = amountADesired;
    }
}