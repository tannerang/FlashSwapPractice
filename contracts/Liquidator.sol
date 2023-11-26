// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";
import { IFakeLendingProtocol } from "./interfaces/IFakeLendingProtocol.sol";
//import { TestERC20 } from "./test/TestERC20.sol";

// This is liquidator contract for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

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
        (uint256 repayAmount, address path0, address path1) = abi.decode(data, (uint256, address, address));

        require(
            msg.sender == IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path0, path1), 
            "Msg sender is not correct"
            );
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");
        
        // call liquidate, let 80 usdc to be 1 eth
        IERC20(path1).approve(_FAKE_LENDING_PROTOCOL, 10 ** 18);
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();

        // deposit ETH to WETH9 
        IWETH(path0).deposit{ value: repayAmount}();

        // repay WETH to uniswap pool
        IERC20(path0).transfer(msg.sender, repayAmount);

        // check profit
        require(address(this).balance >= _MINIMUM_PROFIT, "Profit must be greater than 0.01 eth");
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        require(amountOut > 0, "AmountOut must be greater than 0");
        // TODO
        // swapETHForExactTokens (eth/usdc) 不能走route 因為無法傳入data執行uniswapV2Call

        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0],path[1]);

        // (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        // uint256[] memory repayAmount = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountIn(
        //     amountOut, 
        //     reserve0, 
        //     reserve1);

        uint256[] memory repayAmount = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amountOut, path);
        IUniswapV2Pair(pair).swap(0, amountOut, address(this), abi.encode(repayAmount[0], path[0], path[1]));

        // usdc: pair => Liquidator contract -> FakeLendingProtocol contract
        // ETH: FakeLendingProtocol contract -> Liquidator contract -> WETH -> pair
    }

    receive() external payable {}
}
