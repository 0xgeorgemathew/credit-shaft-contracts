// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {CollateralManager} from "./CollateralManager.sol";

interface ICBLP {
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

library CreditShaftViews {
    using CollateralManager for mapping(uint256 => CollateralManager.Loan);

    struct Loan {
        address borrower;
        uint256 borrowedETH;
        uint256 ethCollateral;
        uint256 preAuthAmountUSD;
        uint256 interestRate;
        uint256 createdAt;
        uint256 preAuthExpiry;
        bool isActive;
        string stripePaymentIntentId;
        string stripeCustomerId;
        string stripePaymentMethodId;
    }


    function getUserLoans(
        mapping(address => uint256[]) storage userLoans,
        address user
    ) internal view returns (uint256[] memory) {
        return userLoans[user];
    }

    function getLoanDetails(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId
    ) internal view returns (
        address borrower,
        uint256 borrowedETH,
        uint256 ethCollateral,
        uint256 preAuthAmountUSD,
        uint256 currentInterest,
        uint256 totalRepayAmount,
        uint256 createdAt,
        uint256 preAuthExpiry,
        bool isActive,
        bool isExpired
    ) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = loan.borrowedETH > 0 ? (loan.borrowedETH * 8 * timeElapsed) / (365 days * 100) : 0;

        return (
            loan.borrower,
            loan.borrowedETH,
            loan.ethCollateral,
            loan.preAuthAmountUSD,
            interest,
            loan.borrowedETH + interest,
            loan.createdAt,
            loan.preAuthExpiry,
            loan.isActive,
            block.timestamp >= loan.preAuthExpiry
        );
    }

    function getActiveLoansForUser(
        mapping(uint256 => Loan) storage loans,
        mapping(address => uint256[]) storage userLoans,
        address user
    ) internal view returns (uint256[] memory activeLoans, uint256 count) {
        uint256[] memory userLoanIds = userLoans[user];
        uint256[] memory tempActive = new uint256[](userLoanIds.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < userLoanIds.length; i++) {
            if (loans[userLoanIds[i]].borrowedETH > 0) {
                tempActive[activeCount] = userLoanIds[i];
                activeCount++;
            }
        }

        activeLoans = new uint256[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            activeLoans[i] = tempActive[i];
        }

        return (activeLoans, activeCount);
    }

    function getRepayAmount(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId
    ) internal view returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];

        if (loan.borrowedETH == 0) return 0;

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * 8 * timeElapsed) / (365 days * 100);
        uint256 bufferInterest = (loan.borrowedETH * 8 * 1 hours) / (365 days * 100);
        return loan.borrowedETH + interest + bufferInterest;
    }

    function hasActiveLoan(
        mapping(uint256 => Loan) storage loans,
        mapping(address => uint256[]) storage userLoans,
        address user
    ) internal view returns (bool) {
        uint256[] memory userLoanIds = userLoans[user];
        for (uint256 i = 0; i < userLoanIds.length; i++) {
            if (loans[userLoanIds[i]].borrowedETH > 0) return true;
        }
        return false;
    }

    function getUserLPBalance(
        ICBLP lpToken,
        address user
    ) internal view returns (uint256 shares, uint256 value) {
        shares = lpToken.balanceOf(user);
        value = shares > 0 ? lpToken.convertToAssets(shares) : 0;
    }

    function getPoolStats(
        uint256 totalLiquidity,
        uint256 totalBorrowed
    ) internal pure returns (uint256 totalLiq, uint256 totalBorr, uint256 available, uint256 utilization) {
        totalLiq = totalLiquidity;
        totalBorr = totalBorrowed;
        available = totalLiquidity > totalBorrowed ? totalLiquidity - totalBorrowed : 0;
        utilization = totalLiquidity > 0 ? (totalBorrowed * 10000) / totalLiquidity : 0; // basis points
    }

}