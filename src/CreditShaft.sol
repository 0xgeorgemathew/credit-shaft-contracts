// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {InterestBearingCBLP} from "./InterestBearingCBLP.sol"; // Import the new IBT

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

    ICBLP public lpToken;

    uint256 public nextLoanId = 1;
    uint256 public totalLiquidity;
    uint256 public totalBorrowed;
    uint256 public totalInterestAccrued;
    uint256 public constant BORROW_APY = 10; // 10% APY
    uint256 public constant LP_SHARE = 80; // 80% to LPs, 20% to protocol
    uint256 public protocolFees;

    // Chainlink Functions
    uint64 public subscriptionId;
    bytes32 public donID;
    uint32 public gasLimit = 300000;
    string public source;
    uint8 public donHostedSecretsSlotID = 0;
    uint64 public donHostedSecretsVersion;

    // Events
    event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 amountETH, uint256 preAuthUSD);
    event LoanRepaid(uint256 indexed loanId, uint256 amountRepaid, uint256 interest);
    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);
    event PreAuthCharged(uint256 indexed loanId, string paymentIntentId);
    event ChainlinkRequestSent(bytes32 indexed requestId, uint256 loanId);
    event RewardsDistributed(uint256 toLPs, uint256 toProtocol);

    // ---  CONSTRUCTOR ---
    constructor(address router, uint64 _subscriptionId, bytes32 _donID)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        subscriptionId = _subscriptionId;
        donID = _donID;
        // Deploy the LP token and set this contract as its owner
        InterestBearingCBLP _lpToken = new InterestBearingCBLP(address(this));
        _lpToken.transferOwnership(address(this));
        lpToken = ICBLP(address(_lpToken));

        source = _getStripeChargeSource();
    }

    // Core Functions
    function borrowETH(
        uint256 preAuthAmountUSD,
        uint256 preAuthDurationDays,
        string memory stripePaymentIntentId,
        string memory stripeCustomerId,
        string memory stripePaymentMethodId
    ) external nonReentrant returns (uint256 loanId) {
        require(preAuthAmountUSD > 0, "Invalid preAuth amount");
        require(bytes(stripePaymentIntentId).length > 0, "Invalid payment intent");

        uint256 ethPrice = 2500;
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
            preAuthExpiry: block.timestamp + (preAuthDurationDays * 1 days),
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
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(loan.borrower == msg.sender, "Not loan owner");

        uint256 timeElapsed = block.timestamp - loan.createdAt;
        uint256 interest = (loan.borrowedETH * BORROW_APY * timeElapsed) / (365 days * 100);
        uint256 totalRepayment = loan.borrowedETH + interest;

        require(msg.value >= totalRepayment, "Insufficient repayment");

        loan.isActive = false;
        totalBorrowed -= loan.borrowedETH;

        uint256 lpReward = (interest * LP_SHARE) / 100;
        uint256 protocolReward = interest - lpReward;
        protocolFees += protocolReward;

        // This now implicitly increases the value of each LP share
        totalLiquidity += lpReward;
        totalInterestAccrued += lpReward;

        emit LoanRepaid(loanId, totalRepayment, interest);
        emit RewardsDistributed(lpReward, protocolReward);

        if (msg.value > totalRepayment) {
            (bool refunded,) = msg.sender.call{value: msg.value - totalRepayment}("");
            require(refunded, "Refund failed");
        }
    }

    // --- MODIFIED addLiquidity ---
    function addLiquidity() external payable nonReentrant {
        require(msg.value > 0, "No ETH sent");
        uint256 amount = msg.value;

        // Calculate shares to mint before updating totalLiquidity
        uint256 shares = lpToken.convertToShares(amount);

        totalLiquidity += amount;
        lpToken.mint(msg.sender, shares);

        emit LiquidityAdded(msg.sender, amount);
    }

    // --- MODIFIED removeLiquidity ---
    function removeLiquidity(uint256 shares) external nonReentrant {
        require(shares > 0, "Invalid shares");
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

        require(loan.isActive, "Loan not active");
        require(block.timestamp >= loan.preAuthExpiry, "Not expired");

        _chargePreAuth(loanId);
    }

    function chargePreAuth(uint256 loanId) external onlyOwner {
        require(loans[loanId].isActive, "Loan not active");
        _chargePreAuth(loanId);
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

    function fulfillRequest(bytes32 requestId, bytes memory, /* response */ bytes memory err) internal override {
        uint256 loanId = requestToLoanId[requestId];

        if (err.length > 0) {
            return;
        }

        loans[loanId].isActive = false;
        totalBorrowed -= loans[loanId].borrowedETH;

        emit PreAuthCharged(loanId, loans[loanId].stripePaymentIntentId);
    }

    // Helper Functions (unchanged)
    function _getStripeChargeSource() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "const paymentIntentId = args[0];",
                "const amountToCapture = args[1];",
                "if (!secrets.STRIPE_SECRET_KEY) { throw Error('STRIPE_SECRET_KEY required'); }",
                "if (!paymentIntentId) { throw Error('Payment Intent ID required'); }",
                "const isSimulation = secrets.STRIPE_SECRET_KEY.includes('mock_key_for_simulation');",
                "if (isSimulation) {",
                "  return Functions.encodeString(JSON.stringify({",
                "    success: true,",
                "    paymentIntentId: paymentIntentId,",
                "    status: 'succeeded',",
                "    amountCaptured: amountToCapture || 5000,",
                "    currency: 'usd',",
                "    simulation: true",
                "  }));",
                "}",
                "let url = `https://api.stripe.com/v1/payment_intents/${paymentIntentId}/capture`;",
                "if (amountToCapture) { url += `?amount_to_capture=${amountToCapture}`; }",
                "const stripeRequest = Functions.makeHttpRequest({",
                "  url: url,",
                "  method: 'POST',",
                "  headers: { Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}` }",
                "});",
                "await stripeRequest;",
                "const statusResponse = await Functions.makeHttpRequest({",
                "  url: `https://api.stripe.com/v1/payment_intents/${paymentIntentId}`,",
                "  method: 'GET',",
                "  headers: { Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}` }",
                "});",
                "const paymentIntent = statusResponse.data;",
                "return Functions.encodeString(JSON.stringify({",
                "  success: paymentIntent.status === 'succeeded',",
                "  paymentIntentId: paymentIntent.id,",
                "  status: paymentIntent.status,",
                "  amountCaptured: paymentIntent.amount_received,",
                "  currency: paymentIntent.currency",
                "}));"
            )
        );
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
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // View Functions
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    function getUserLoans(address user) external view returns (uint256[] memory) {
        return userLoans[user];
    }

    function getLPShares(address provider) external view returns (uint256) {
        return lpToken.balanceOf(provider);
    }

    // --- MODIFIED getLPValue ---
    function getLPValue(address provider) external view returns (uint256) {
        uint256 shares = lpToken.balanceOf(provider);
        if (shares == 0) return 0;
        return lpToken.convertToAssets(shares);
    }

    function getPoolAPY() external view returns (uint256) {
        if (totalLiquidity == 0 || totalBorrowed == 0) return 0;
        uint256 utilization = (totalBorrowed * 100) / totalLiquidity;
        return (BORROW_APY * LP_SHARE * utilization) / 10000;
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

    receive() external payable {}
}
