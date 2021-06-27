// SPDX-License-Identifier: MIT

pragma solidity ^0.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "./ILendingProtocol.sol";
import "hardhat/console.sol";

contract VulnerableLendingProtocol is ILendingProtocol {
    using FixedPoint for *;

    address private constant daiAddress =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant daiEthPairAddress =
        0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    IERC20 private constant Dai = IERC20(daiAddress);

    mapping(address => uint256) depositedCollateral;
    mapping(address => uint256) borrowedDai;

    constructor() public {}

    /**
     * Calculates the mid price of ETH (in DAI) from calculating the liquidity reserves.
     * This is vulnerable to instantaneous price movements as we rely solely on Uniswap
     * as an on-chain price oracle.
     */
    function getEthPrice() public view returns (uint256) {
        (uint112 daiReserve, uint112 ethReserve, ) =
            IUniswapV2Pair(daiEthPairAddress).getReserves();

        return FixedPoint.fraction(daiReserve, ethReserve).decode();
    }

    /**
     * Deposit ETH as collateral.
     */
    function depositCollateral() external payable override {
        // console.log("Depositing collateral");
        depositedCollateral[msg.sender] += msg.value;
    }

    /**
     * Withdraw ETH from collateral.
     */
    function withdrawCollateral(uint256 withdrawAmount) external override {
        address borrower = msg.sender;
        uint256 daiPerEth = getEthPrice();
        uint256 requiredCollateral =
            (150 * (borrowedDai[borrower] - withdrawAmount)) /
                (100 * daiPerEth);
        require(
            depositedCollateral[borrower] >= requiredCollateral,
            "Collateralisation ratio must must be >=150% after withdrawing ETH"
        );

        depositedCollateral[msg.sender] -= withdrawAmount;
        (bool ethTransferred, ) = msg.sender.call{value: withdrawAmount}("");
        require(ethTransferred, "Error transferring ETH to borrower");
    }

    /**
     * Borrow DAI, using deposited ETH as collateral at a minimum of
     * 150% collateralisation ratio.
     */
    function borrowDai(uint256 daiBorrowAmount) external override {
        // Check that there is enough liquidity
        uint256 daiLiquidity = Dai.balanceOf(address(this));
        console.log(
            "Trying to borrow: %s, Liquidity: %s",
            daiBorrowAmount,
            daiLiquidity
        );
        require(
            daiLiquidity >= daiBorrowAmount,
            "Not enough liquidity in the DAI lending pool!"
        );
        address borrower = msg.sender;
        uint256 daiPerEth = getEthPrice();
        console.log("ETH price: %s", daiPerEth);
        // Check that user has sufficient available collateral
        uint256 requiredCollateral =
            (150 * (daiBorrowAmount + borrowedDai[borrower])) /
                (100 * daiPerEth);
        console.log("Required coll: %s", requiredCollateral);
        require(
            depositedCollateral[borrower] >= requiredCollateral,
            "Collateralisation ratio after borrowing must be >=150%"
        );

        console.log("Lending!");
        // Update borrower's books & lend DAI to borrower
        borrowedDai[borrower] += daiBorrowAmount;
        bool daiTransferred = Dai.transfer(borrower, daiBorrowAmount);
        require(daiTransferred, "Error transferring DAI to borrower");
    }

    /**
     * Repay DAI
     */
    function repayDai(uint256 repayAmount) external override {
        address borrower = msg.sender;
        uint256 cappedRepayAmount =
            min(borrowedDai[borrower] - repayAmount, repayAmount);
        borrowedDai[borrower] -= cappedRepayAmount;
        bool daiTransferred =
            Dai.transferFrom(borrower, address(this), cappedRepayAmount);
        require(daiTransferred, "Error transferring DAI to lending pool");
    }

    function isLiquidatable(address borrower)
        external
        view
        override
        returns (bool)
    {
        uint256 daiPerEth = getEthPrice();
        uint256 requiredCollateral =
            (150 * borrowedDai[borrower]) / (100 * daiPerEth);
        // Less than 150% CR -> liquidatable
        return (depositedCollateral[borrower] < requiredCollateral);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
