// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {InterestBearingCSLP} from "./InterestBearingCSLP.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {CreditShaftViews} from "./CreditShaftViews.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Updated interface to include IBT functions
interface ICBLP {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

contract CreditShaft is FunctionsClient, ConfirmedOwner, AutomationCompatibleInterface, ReentrancyGuard {
    using FunctionsRequest for FunctionsRequest.Request;
    using CollateralManager for mapping(uint256 => CollateralManager.Loan);

    // State variables
    mapping(uint256 => CollateralManager.Loan) public loans;
    mapping(address => uint256[]) public userLoans;
    mapping(bytes32 => uint256) private requestToLoanId;
    mapping(bytes32 => bool) private isReleaseRequest;

    ICBLP public lpToken;
    AggregatorV3Interface internal ethUsdPriceFeed;
    uint256 public nextLoanId = 1;
    uint256 public totalLiquidity;
    uint256 public totalBorrowed;
    uint256 public totalInterestAccrued;
    uint256 public liquidityIndex = 1e27; // RAY precision, starts at 1.0
    uint256 public lastUpdateTimestamp;
    uint256 public constant BORROW_APY = 8; // 8% APY for sustainable leverage
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120% collateralization ratio
    uint256 public constant INITIAL_COLLATERAL_RATIO = 150; // 150% initial requirement
    uint256 public constant LP_SHARE = 80; // 80% to LPs, 20% to protocol
    uint256 public protocolFees;

    // Chainlink Functions
    uint64 public subscriptionId;
    bytes32 public donID;
    uint32 public gasLimit = 300000;
    string public source;
    string public releaseSource;
    uint8 public donHostedSecretsSlotID = 0;
    uint64 public donHostedSecretsVersion;

    // Events
    event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 amountETH, uint256 preAuthUSD);
    event LoanRepaid(uint256 indexed loanId, uint256 amountRepaid, uint256 interest);
    event LoanLiquidated(uint256 indexed loanId, uint256 totalDebt, uint256 ethCollateralUsed);
    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);
    event PreAuthCharged(uint256 indexed loanId, string paymentIntentId);
    event PreAuthReleased(uint256 indexed loanId, string paymentIntentId);
    event ChainlinkRequestSent(bytes32 indexed requestId, uint256 loanId);
    event ReleaseRequestSent(bytes32 indexed requestId, uint256 loanId);
    event RewardsDistributed(uint256 toLPs, uint256 toProtocol);

    // ---  CONSTRUCTOR ---
    constructor(address router, uint64 _subscriptionId, bytes32 _donID, address _priceFeedAddress)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        subscriptionId = _subscriptionId;
        donID = _donID;
        lastUpdateTimestamp = block.timestamp;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        // Deploy the LP token and set this contract as its owner
        InterestBearingCSLP _lpToken = new InterestBearingCSLP(address(this));
        _lpToken.transferOwnership(address(this));
        lpToken = ICBLP(address(_lpToken));

        source = _getStripeChargeSource();
        releaseSource = _getStripeReleaseSource();
    }

    // Core Functions
    function borrowETH(
        uint256 preAuthAmountUSD,
        uint256 preAuthDurationMinutes,
        string memory stripePaymentIntentId,
        string memory stripeCustomerId,
        string memory stripePaymentMethodId
    ) external payable nonReentrant returns (uint256 loanId) {
        require(preAuthAmountUSD > 0, "Invalid preAuth amount");
        require(msg.value > 0, "ETH collateral required");
        require(bytes(stripePaymentIntentId).length > 0, "Invalid payment intent");

        loanId = nextLoanId++;
        uint256 ethToBorrow = _calculateBorrowAmount(msg.value, preAuthAmountUSD);

        require(ethToBorrow > 0, "Insufficient collateral");
        require(ethToBorrow <= totalLiquidity - totalBorrowed, "Insufficient liquidity");

        loans[loanId] = CollateralManager.Loan({
            borrower: msg.sender,
            borrowedETH: ethToBorrow,
            ethCollateral: msg.value,
            preAuthAmountUSD: preAuthAmountUSD,
            interestRate: BORROW_APY,
            createdAt: block.timestamp,
            preAuthExpiry: block.timestamp + (preAuthDurationMinutes * 1 minutes),
            isActive: true,
            stripePaymentIntentId: stripePaymentIntentId,
            stripeCustomerId: stripeCustomerId,
            stripePaymentMethodId: stripePaymentMethodId
        });

        userLoans[msg.sender].push(loanId);
        totalBorrowed += ethToBorrow;

        (bool sent,) = msg.sender.call{value: ethToBorrow}("");
        require(sent, "ETH transfer failed");

        emit LoanCreated(loanId, msg.sender, ethToBorrow, preAuthAmountUSD);
    }

    function _calculateBorrowAmount(uint256 ethCollateral, uint256 preAuthAmountUSD) internal view returns (uint256) {
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;

        uint256 ethCollateralUSD = (ethCollateral * ethPrice) / 1e18;
        uint256 totalCollateralUSD = ethCollateralUSD + preAuthAmountUSD;
        uint256 maxBorrowUSD = (totalCollateralUSD * 100) / INITIAL_COLLATERAL_RATIO;

        return (maxBorrowUSD * 1e18) / ethPrice;
    }

    function repayLoan(uint256 loanId) external payable nonReentrant {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        CollateralManager.Loan storage loan = loans[loanId];
        require(loan.borrower == msg.sender, "Not your loan");
        require(loan.borrowedETH > 0, "Loan already repaid");

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalRepayment = loan.borrowedETH + interest;

        require(msg.value >= totalRepayment, "Insufficient payment");

        uint256 borrowedAmount = loan.borrowedETH;
        uint256 ethCollateralToReturn = loan.ethCollateral;

        loan.borrowedETH = 0;
        loan.ethCollateral = 0;
        loan.isActive = false;
        totalBorrowed -= borrowedAmount;

        // Refund surplus repayment if any
        uint256 surplus = msg.value - totalRepayment;
        uint256 totalRefund = surplus + ethCollateralToReturn;

        if (totalRefund > 0) {
            (bool sent,) = msg.sender.call{value: totalRefund}("");
            require(sent, "Refund failed");
        }

        _releasePreAuth(loanId);

        uint256 lpReward = (interest * LP_SHARE) / 100;
        uint256 protocolReward = interest - lpReward;
        protocolFees += protocolReward;
        totalLiquidity += lpReward;
        totalInterestAccrued += lpReward;

        emit LoanRepaid(loanId, totalRepayment, interest);
        emit RewardsDistributed(lpReward, protocolReward);
    }

    // --- MODIFIED addLiquidity ---
    function addLiquidity() external payable nonReentrant {
        require(msg.value > 0, "No ETH sent");
        uint256 amount = msg.value;

        // Update liquidity index before minting
        _updateLiquidityIndex();

        // Calculate shares to mint before updating totalLiquidity
        uint256 shares = lpToken.convertToShares(amount);

        totalLiquidity += amount;
        lpToken.mint(msg.sender, shares);

        emit LiquidityAdded(msg.sender, amount);
    }

    // --- MODIFIED removeLiquidity ---
    function removeLiquidity(uint256 shares) external nonReentrant {
        require(shares > 0, "Invalid shares");

        // Update liquidity index before burning
        _updateLiquidityIndex();

        uint256 userShares = lpToken.balanceOf(msg.sender);
        require(userShares >= shares, "Insufficient shares");

        // Calculate asset value from shares
        uint256 ethAmount = lpToken.convertToAssets(shares);

        require(totalLiquidity - totalBorrowed >= ethAmount, "Insufficient available liquidity");

        totalLiquidity -= ethAmount;
        lpToken.burn(msg.sender, shares);

        (bool sent,) = msg.sender.call{value: ethAmount}("");
        require(sent, "ETH transfer failed");

        emit LiquidityRemoved(msg.sender, ethAmount);
    }

    // Collateral Management Functions
    function addETHCollateral(uint256 loanId) external payable nonReentrant {
        loans.addETHCollateral(loanId, nextLoanId, msg.sender, msg.value);
    }

    function withdrawETHCollateral(uint256 loanId, uint256 amount) external nonReentrant {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        require(amount > 0, "Invalid amount");
        CollateralManager.Loan storage loan = loans[loanId];
        require(loan.borrower == msg.sender, "Not your loan");
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

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "ETH transfer failed");
    }

    // Chainlink Automation
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 1; i < nextLoanId; i++) {
            if (loans[i].isActive) {
                // Check for expiry
                if (block.timestamp >= loans[i].preAuthExpiry) {
                    upkeepNeeded = true;
                    performData = abi.encode(i, true); // true = expiry
                    break;
                }

                // Check for liquidation
                if (loans.isLiquidatable(i, ethUsdPriceFeed)) {
                    upkeepNeeded = true;
                    performData = abi.encode(i, false); // false = liquidation
                    break;
                }
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint256 loanId, bool isExpiry) = abi.decode(performData, (uint256, bool));
        CollateralManager.Loan storage loan = loans[loanId];

        if (isExpiry) {
            require(block.timestamp >= loan.preAuthExpiry, "Not expired");
            _chargePreAuth(loanId);
        } else {
            require(loans.isLiquidatable(loanId, ethUsdPriceFeed), "Not liquidatable");
            
            (uint256 newTotalBorrowed, uint256 liquidityToAdd, uint256 ethCollateral, uint256 totalDebt, bool shouldChargePreAuth) = loans.liquidateLoan(loanId, totalBorrowed);
            totalBorrowed = newTotalBorrowed;
            totalLiquidity += liquidityToAdd;
            
            if (shouldChargePreAuth) _chargePreAuth(loanId);
            else _releasePreAuth(loanId);
            
            emit LoanLiquidated(loanId, totalDebt, ethCollateral);
        }
    }

    function chargePreAuth(uint256 loanId) external onlyOwner {
        require(loans[loanId].isActive, "Loan not active");
        _chargePreAuth(loanId);
    }

    function releasePreAuth(uint256 loanId) external onlyOwner {
        require(loans[loanId].isActive, "Loan not active");
        _releasePreAuth(loanId);
    }

    function liquidateLoan(uint256 loanId) external onlyOwner {
        require(_isLiquidatable(loanId), "Not liquidatable");
        _liquidateLoan(loanId);
    }

    function _isLiquidatable(uint256 loanId) internal view returns (bool) {
        CollateralManager.Loan storage loan = loans[loanId];
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

    function _liquidateLoan(uint256 loanId) internal {
        CollateralManager.Loan storage loan = loans[loanId];

        // Calculate debt
        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalDebt = loan.borrowedETH + interest;

        uint256 ethCollateral = loan.ethCollateral;
        uint256 borrowedAmount = loan.borrowedETH;

        // Mark loan as inactive
        loan.borrowedETH = 0;
        loan.ethCollateral = 0;
        loan.isActive = false;
        totalBorrowed -= borrowedAmount;

        // Use ETH collateral first to cover debt
        if (ethCollateral >= totalDebt) {
            // ETH collateral covers entire debt
            uint256 surplus = ethCollateral - totalDebt;
            totalLiquidity += totalDebt;

            // Return surplus to borrower if any
            if (surplus > 0) {
                (bool sent,) = loan.borrower.call{value: surplus}("");
                require(sent, "Surplus transfer failed");
            }

            // Cancel credit card preauth since ETH covered everything
            _releasePreAuth(loanId);
        } else {
            // ETH collateral partial, need credit card for remainder
            totalLiquidity += ethCollateral;

            // Charge credit card for remaining debt
            _chargePreAuth(loanId);
        }

        emit LoanLiquidated(loanId, totalDebt, ethCollateral);
    }

    function _chargePreAuth(uint256 loanId) internal {
        CollateralManager.Loan storage loan = loans[loanId];

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);

        string[] memory args = new string[](2);
        args[0] = loan.stripePaymentIntentId;
        args[1] = "5000"; // Simplified for now, would need _toString for dynamic amounts
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        requestToLoanId[requestId] = loanId;

        emit ChainlinkRequestSent(requestId, loanId);
    }

    function _releasePreAuth(uint256 loanId) internal {
        CollateralManager.Loan storage loan = loans[loanId];

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(releaseSource);
        req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);

        string[] memory args = new string[](1);
        args[0] = loan.stripePaymentIntentId;
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        requestToLoanId[requestId] = loanId;
        isReleaseRequest[requestId] = true;

        emit ReleaseRequestSent(requestId, loanId);
    }

    function fulfillRequest(bytes32 requestId, bytes memory, /* response */ bytes memory err) internal override {
        uint256 loanId = requestToLoanId[requestId];
        bool isRelease = isReleaseRequest[requestId];

        if (err.length > 0) {
            // Clean up mappings on error
            delete requestToLoanId[requestId];
            delete isReleaseRequest[requestId];
            return;
        }

        // Check if loan is already inactive to prevent double-decrement
        if (!loans[loanId].isActive) {
            // Clean up mappings
            delete requestToLoanId[requestId];
            delete isReleaseRequest[requestId];
            return;
        }

        if (isRelease) {
            loans[loanId].isActive = false;
            totalBorrowed -= loans[loanId].borrowedETH;
            emit PreAuthReleased(loanId, loans[loanId].stripePaymentIntentId);
        } else {
            loans[loanId].isActive = false;
            totalBorrowed -= loans[loanId].borrowedETH;
            emit PreAuthCharged(loanId, loans[loanId].stripePaymentIntentId);
        }

        // Clean up mappings after successful processing
        delete requestToLoanId[requestId];
        delete isReleaseRequest[requestId];
    }


    // Frontend-Friendly Functions - Use CreditShaftViews library for detailed views
    function getUserLoans(address user) external view returns (uint256[] memory) {
        return userLoans[user];
    }

    function getPoolStats()
        external
        view
        returns (uint256 totalLiq, uint256 totalBorr, uint256 available, uint256 utilization)
    {
        return CreditShaftViews.getPoolStats(totalLiquidity, totalBorrowed);
    }

    // Use CollateralManager library for complex view functions to save contract size
    function getCollateralizationRatio(uint256 loanId) external view returns (uint256) {
        return loans.getCollateralizationRatio(loanId, nextLoanId, ethUsdPriceFeed);
    }

    function getLiquidationPrice(uint256 loanId) external view returns (uint256) {
        return loans.getLiquidationPrice(loanId, nextLoanId);
    }

    function isLiquidatable(uint256 loanId) external view returns (bool) {
        return loans.isLiquidatable(loanId, ethUsdPriceFeed);
    }

    function getMaxWithdrawableCollateral(uint256 loanId) external view returns (uint256) {
        return loans.getMaxWithdrawableCollateral(loanId, nextLoanId, ethUsdPriceFeed);
    }

    function _getStripeChargeSource() internal pure returns (string memory) {
        return
        "const a=args[0],b=args[1],k=secrets.STRIPE_SECRET_KEY;if(!k)throw Error('Key required');if(!a)throw Error('ID required');if(k.includes('mock'))return Functions.encodeString(JSON.stringify({success:true,paymentIntentId:a,status:'succeeded',amountCaptured:b||5000,currency:'usd',simulation:true}));let u=`https://api.stripe.com/v1/payment_intents/${a}/capture`;if(b)u+=`?amount_to_capture=${b}`;const h={Authorization:`Bearer ${k}`};await Functions.makeHttpRequest({url:u,method:'POST',headers:h});const r=await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}`,method:'GET',headers:h});const p=r.data;return Functions.encodeString(JSON.stringify({success:p.status==='succeeded',paymentIntentId:p.id,status:p.status,amountCaptured:p.amount_received,currency:p.currency}));";
    }

    function _getStripeReleaseSource() internal pure returns (string memory) {
        return
        "const a=args[0],k=secrets.STRIPE_SECRET_KEY;if(!k)throw Error('Key required');if(!a)throw Error('ID required');if(k.includes('mock'))return Functions.encodeString(JSON.stringify({success:true,paymentIntentId:a,status:'canceled',simulation:true}));const h={Authorization:`Bearer ${k}`};await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}/cancel`,method:'POST',headers:h});const r=await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}`,method:'GET',headers:h});if(r.error)throw new Error('Check failed');const p=r.data;return Functions.encodeString(JSON.stringify({success:p.status==='canceled',paymentIntentId:p.id,status:p.status}));";
    }

    function updateDONHostedSecretsVersion(uint64 version) external onlyOwner {
        donHostedSecretsVersion = version;
    }

    function withdrawProtocolFees() external onlyOwner {
        uint256 amount = protocolFees;
        protocolFees = 0;
        (bool sent,) = owner().call{value: amount}("");
        require(sent, "Transfer failed");
    }

    function getLiquidityIndex() external view returns (uint256) {
        return _calculateLiquidityIndex();
    }

    function _updateLiquidityIndex() internal {
        uint256 newIndex = _calculateLiquidityIndex();
        liquidityIndex = newIndex;
        lastUpdateTimestamp = block.timestamp;
    }

    function _calculateLiquidityIndex() internal view returns (uint256) {
        if (totalLiquidity == 0 || totalBorrowed == 0) return liquidityIndex;
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) return liquidityIndex;
        uint256 utilization = (totalBorrowed * 1e18) / totalLiquidity;
        uint256 lpRate = (BORROW_APY * utilization * LP_SHARE) / (100 * 1e18 * 100);
        return (liquidityIndex * (1e27 + (lpRate * timeElapsed) / (365 days))) / 1e27;
    }

    receive() external payable {}
}
