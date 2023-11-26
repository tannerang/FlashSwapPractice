// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        // Decode data
        (
            uint256 repayAmount, 
            address priceLowerPool, 
            address priceHigherPool,
            uint256 borrowETH
        ) = abi.decode(data, (uint256, address, address, uint256));

        // Basic checking
        require(
            msg.sender == priceLowerPool, 
            "Msg sender is not correct"
            );
        require(sender == address(this), "Sender must be this contract");    
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // Get amountOut of USDC
        (uint112 reserveWETH, uint112 reserveUSDC,) = IUniswapV2Pair(priceHigherPool).getReserves();
        uint256 amountOutUSDC = _getAmountOut(borrowETH, reserveWETH, reserveUSDC);

        // Swap WETH for USDC in higher price pool
        IERC20(IUniswapV2Pair(priceHigherPool).token0()).transfer(priceHigherPool, borrowETH);
        IUniswapV2Pair(priceHigherPool).swap(0, amountOutUSDC, address(this), "");

        // Repay USDC to lower pool
        IERC20(IUniswapV2Pair(priceLowerPool).token1()).transfer(priceLowerPool, repayAmount);
        }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO
        // Get reserves
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(priceLowerPool).getReserves();

        // Get amountIn
        uint256 repayAmount = _getAmountIn(borrowETH, reserve1, reserve0);

        // Excute swap USDC for WETH with data
        IUniswapV2Pair(priceLowerPool).swap(
            borrowETH, 
            0, 
            address(this), 
            abi.encode(repayAmount, priceLowerPool, priceHigherPool, borrowETH)
        );
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
