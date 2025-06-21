// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

library CollateralManager {
    uint256 public constant BORROW_APY = 8;
    uint256 public constant LIQUIDATION_THRESHOLD = 120;
    
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

    event LoanLiquidated(uint256 indexed loanId, uint256 totalDebt, uint256 ethCollateralUsed);

    function addETHCollateral(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId,
        address sender,
        uint256 value
    ) external {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        require(value > 0, "No ETH sent");
        Loan storage loan = loans[loanId];
        require(loan.borrower == sender, "Not your loan");
        require(loan.borrowedETH > 0, "Loan not active");

        loan.ethCollateral += value;
    }

    function withdrawETHCollateral(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId,
        uint256 amount,
        address sender,
        AggregatorV3Interface ethUsdPriceFeed
    ) external returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        require(amount > 0, "Invalid amount");
        Loan storage loan = loans[loanId];
        require(loan.borrower == sender, "Not your loan");
        require(loan.borrowedETH > 0, "Loan not active");
        require(loan.ethCollateral >= amount, "Insufficient collateral");

        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;
        
        // Calculate remaining collateral after withdrawal
        uint256 remainingETHCollateral = loan.ethCollateral - amount;
        uint256 remainingETHCollateralUSD = (remainingETHCollateral * ethPrice) / 1e18;
        uint256 totalRemainingCollateralUSD = remainingETHCollateralUSD + loan.preAuthAmountUSD;
        
        // Current debt value in USD
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebtUSD = ((loan.borrowedETH + interest) * ethPrice) / 1e18;
        
        // Ensure collateralization ratio stays above 120%
        require(
            totalRemainingCollateralUSD >= (totalDebtUSD * LIQUIDATION_THRESHOLD) / 100,
            "Would breach liquidation threshold"
        );

        loan.ethCollateral -= amount;
        return amount;
    }

    function isLiquidatable(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        AggregatorV3Interface ethUsdPriceFeed
    ) external view returns (bool) {
        Loan storage loan = loans[loanId];
        if (!loan.isActive || loan.borrowedETH == 0) return false;

        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;
        
        // Calculate current debt with accrued interest
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebtUSD = ((loan.borrowedETH + interest) * ethPrice) / 1e18;
        
        // Calculate total collateral value
        uint256 ethCollateralUSD = (loan.ethCollateral * ethPrice) / 1e18;
        uint256 totalCollateralUSD = ethCollateralUSD + loan.preAuthAmountUSD;
        
        // Check if collateralization ratio is below 120%
        return totalCollateralUSD < (totalDebtUSD * LIQUIDATION_THRESHOLD) / 100;
    }

    function liquidateLoan(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 totalBorrowed
    ) external returns (uint256 newTotalBorrowed, uint256 liquidityToAdd, uint256 ethCollateral, uint256 totalDebt, bool shouldChargePreAuth) {
        Loan storage loan = loans[loanId];
        
        // Calculate debt
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        totalDebt = loan.borrowedETH + interest;
        
        ethCollateral = loan.ethCollateral;
        uint256 borrowedAmount = loan.borrowedETH;
        
        // Mark loan as inactive
        loan.borrowedETH = 0;
        loan.ethCollateral = 0;
        loan.isActive = false;
        newTotalBorrowed = totalBorrowed - borrowedAmount;
        
        // Use ETH collateral first to cover debt
        if (ethCollateral >= totalDebt) {
            // ETH collateral covers entire debt
            liquidityToAdd = totalDebt;
            shouldChargePreAuth = false; // Release preauth instead
        } else {
            // ETH collateral partial, need credit card for remainder
            liquidityToAdd = ethCollateral;
            shouldChargePreAuth = true;
        }
    }

    function getCollateralizationRatio(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId,
        AggregatorV3Interface ethUsdPriceFeed
    ) external view returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];
        if (!loan.isActive || loan.borrowedETH == 0) return 0;

        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;
        
        // Calculate current debt with interest
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebtUSD = ((loan.borrowedETH + interest) * ethPrice) / 1e18;
        
        // Calculate total collateral value
        uint256 ethCollateralUSD = (loan.ethCollateral * ethPrice) / 1e18;
        uint256 totalCollateralUSD = ethCollateralUSD + loan.preAuthAmountUSD;
        
        // Return ratio as percentage (150 = 150%)
        return totalDebtUSD > 0 ? (totalCollateralUSD * 100) / totalDebtUSD : 0;
    }

    function getLiquidationPrice(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId
    ) external view returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];
        if (!loan.isActive || loan.borrowedETH == 0) return 0;

        // Calculate current debt with interest
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebtUSD = ((loan.borrowedETH + interest) * 1e18) / 1e18;
        
        // At liquidation: (ethCollateral * liquidationPrice + preAuthUSD) = totalDebtUSD * 1.2
        uint256 requiredCollateralUSD = (totalDebtUSD * LIQUIDATION_THRESHOLD) / 100;
        
        if (requiredCollateralUSD <= loan.preAuthAmountUSD) {
            return 0; // Credit card alone covers liquidation threshold
        }
        
        uint256 ethCollateralNeededUSD = requiredCollateralUSD - loan.preAuthAmountUSD;
        return loan.ethCollateral > 0 ? (ethCollateralNeededUSD * 1e18) / loan.ethCollateral : 0;
    }

    function getMaxWithdrawableCollateral(
        mapping(uint256 => Loan) storage loans,
        uint256 loanId,
        uint256 nextLoanId,
        AggregatorV3Interface ethUsdPriceFeed
    ) external view returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];
        if (!loan.isActive || loan.borrowedETH == 0) return loan.ethCollateral;

        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;
        
        // Calculate current debt with interest
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebtUSD = ((loan.borrowedETH + interest) * ethPrice) / 1e18;
        
        // Minimum collateral needed (120% of debt)
        uint256 minCollateralUSD = (totalDebtUSD * LIQUIDATION_THRESHOLD) / 100;
        
        // If credit card covers minimum, can withdraw all ETH
        if (loan.preAuthAmountUSD >= minCollateralUSD) {
            return loan.ethCollateral;
        }
        
        // Calculate minimum ETH collateral needed
        uint256 minETHCollateralUSD = minCollateralUSD - loan.preAuthAmountUSD;
        uint256 minETHCollateral = (minETHCollateralUSD * 1e18) / ethPrice;
        
        return loan.ethCollateral > minETHCollateral ? loan.ethCollateral - minETHCollateral : 0;
    }
}