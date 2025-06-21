// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {InterestBearingShaftETH} from "./InterestBearingShaftETH.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {StripeSources} from "./StripeSources.sol";

// Updated interface to include IBT functions
interface IInterestBearingShaftETH {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

contract CreditShaft is
    FunctionsClient,
    ConfirmedOwner,
    AutomationCompatibleInterface,
    ReentrancyGuard,
    StripeSources
{
    using FunctionsRequest for FunctionsRequest.Request;

    // Structs
    struct Loan {
        address borrower;
        uint256 borrowedETH;
        uint256 preAuthAmountUSD;
        uint256 interestRate;
        uint256 createdAt;
        uint256 preAuthExpiry;
        bool isActive;
        string stripePaymentIntentId;
        string stripeCustomerId;
        string stripePaymentMethodId;
    }

    // State variables
    mapping(uint256 => Loan) public loans;
    mapping(address => uint256[]) public userLoans;
    mapping(bytes32 => uint256) private requestToLoanId;
    mapping(bytes32 => bool) private isReleaseRequest;

    IInterestBearingShaftETH public lpToken;
    AggregatorV3Interface internal ethUsdPriceFeed;
    uint256 public nextLoanId = 1;
    uint256 public totalLiquidity;
    uint256 public totalBorrowed;
    uint256 public totalInterestAccrued;
    uint256 public liquidityIndex = 1e27; // RAY precision, starts at 1.0
    uint256 public lastUpdateTimestamp;
    uint256 public constant BORROW_APY = 10; // 10% APY
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
        InterestBearingShaftETH _lpToken = new InterestBearingShaftETH(address(this));
        _lpToken.transferOwnership(address(this));
        lpToken = IInterestBearingShaftETH(address(_lpToken));

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
    ) external nonReentrant returns (uint256 loanId) {
        require(preAuthAmountUSD > 0, "Invalid preAuth amount");
        require(bytes(stripePaymentIntentId).length > 0, "Invalid payment intent");
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) / 1e8;
        uint256 ltv = 50;
        uint256 ethToBorrow = (preAuthAmountUSD * ltv * 1e18) / (ethPrice * 100);

        require(ethToBorrow <= totalLiquidity - totalBorrowed, "Insufficient liquidity");

        loanId = nextLoanId++;

        loans[loanId] = Loan({
            borrower: msg.sender,
            borrowedETH: ethToBorrow,
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

    function repayLoan(uint256 loanId) external payable nonReentrant {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];
        require(loan.borrower == msg.sender, "Not your loan");
        require(loan.borrowedETH > 0, "Loan already repaid");

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalRepayment = loan.borrowedETH + interest;

        require(msg.value >= totalRepayment, "Insufficient payment");

        uint256 borrowedAmount = loan.borrowedETH;
        loan.borrowedETH = 0;
        loan.isActive = false;
        totalBorrowed -= borrowedAmount;

        // Refund surplus if any
        uint256 surplus = msg.value - totalRepayment;
        if (surplus > 0) {
            (bool sent,) = msg.sender.call{value: surplus}("");
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

    // Chainlink Automation
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 1; i < nextLoanId; i++) {
            if (loans[i].isActive && block.timestamp >= loans[i].preAuthExpiry) {
                upkeepNeeded = true;
                performData = abi.encode(i);
                break;
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 loanId = abi.decode(performData, (uint256));
        Loan storage loan = loans[loanId];

        require(block.timestamp >= loan.preAuthExpiry, "Not expired");

        _chargePreAuth(loanId);
    }

    function chargePreAuth(uint256 loanId) external onlyOwner {
        require(loans[loanId].isActive, "Loan not active");
        _chargePreAuth(loanId);
    }

    function releasePreAuth(uint256 loanId) external onlyOwner {
        require(loans[loanId].isActive, "Loan not active");
        _releasePreAuth(loanId);
    }

    function _chargePreAuth(uint256 loanId) internal {
        Loan storage loan = loans[loanId];

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);

        string[] memory args = new string[](2);
        args[0] = loan.stripePaymentIntentId;
        args[1] = _toString(loan.preAuthAmountUSD * 100);
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        requestToLoanId[requestId] = loanId;

        emit ChainlinkRequestSent(requestId, loanId);
    }

    function _releasePreAuth(uint256 loanId) internal {
        Loan storage loan = loans[loanId];

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

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    // Frontend-Friendly Functions
    function getUserLoans(address user) external view returns (uint256[] memory) {
        return userLoans[user];
    }

    function getLoanDetails(uint256 loanId)
        external
        view
        returns (
            address borrower,
            uint256 borrowedETH,
            uint256 preAuthAmountUSD,
            uint256 currentInterest,
            uint256 totalRepayAmount,
            uint256 createdAt,
            uint256 preAuthExpiry,
            bool isActive,
            bool isExpired
        )
    {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = loan.borrowedETH > 0 ? (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100) : 0;

        return (
            loan.borrower,
            loan.borrowedETH,
            loan.preAuthAmountUSD,
            interest,
            loan.borrowedETH + interest,
            loan.createdAt,
            loan.preAuthExpiry,
            loan.isActive,
            block.timestamp >= loan.preAuthExpiry
        );
    }

    function getActiveLoansForUser(address user) external view returns (uint256[] memory activeLoans, uint256 count) {
        return _getActiveLoansFor(user);
    }

    function getRepayAmount(uint256 loanId) external view returns (uint256) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        Loan storage loan = loans[loanId];

        if (loan.borrowedETH == 0) return 0;

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 bufferInterest = (loan.borrowedETH * BORROW_APY * 1 hours) / (365 days * 100);
        return loan.borrowedETH + interest + bufferInterest;
    }

    function hasActiveLoan(address user) external view returns (bool) {
        return _hasActiveLoanFor(user);
    }

    function getUserLPBalance(address user) external view returns (uint256 shares, uint256 value) {
        shares = lpToken.balanceOf(user);
        value = shares > 0 ? lpToken.convertToAssets(shares) : 0;
    }

    function getPoolStats()
        external
        view
        returns (uint256 totalLiq, uint256 totalBorr, uint256 available, uint256 utilization)
    {
        totalLiq = totalLiquidity;
        totalBorr = totalBorrowed;
        available = totalLiquidity > totalBorrowed ? totalLiquidity - totalBorrowed : 0;
        utilization = totalLiquidity > 0 ? (totalBorrowed * 10000) / totalLiquidity : 0; // basis points
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

    function _getActiveLoansFor(address user) internal view returns (uint256[] memory activeLoans, uint256 count) {
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

    function _hasActiveLoanFor(address user) internal view returns (bool) {
        uint256[] memory userLoanIds = userLoans[user];
        for (uint256 i = 0; i < userLoanIds.length; i++) {
            if (loans[userLoanIds[i]].borrowedETH > 0) return true;
        }
        return false;
    }

    receive() external payable {}
}
