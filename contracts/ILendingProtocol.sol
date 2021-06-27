// SPDX-License-Identifier: MIT

pragma solidity ^0.6;

/**
 * Simple lending protocol that lends DAI using ETH as collateral.
 */
interface ILendingProtocol {
    /**
     * Deposit ETH as collateral.
     */
    function depositCollateral() external payable;

    /**
     * Withdraw ETH from collateral.
     */
    function withdrawCollateral(uint256 withdrawAmount) external;

    /**
     * Borrow DAI, using deposited ETH as collateral at a minimum of
     * 150% collateralisation ratio.
     */
    function borrowDai(uint256 daiBorrowAmount) external;

    /**
     * Repay DAI.
     */
    function repayDai(uint256 repayAmount) external;

    /**
     * Calculates whether or not the borrower is above the
     * required collateralisation ratio or not; at which point their
     * ETH collateral becomes liquidatable.
     */
    function isLiquidatable(address borrower) external view returns (bool);
}
