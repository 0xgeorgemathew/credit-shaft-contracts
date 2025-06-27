// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IUniswapV2Router02} from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

// Interface for MockAggregator compatibility
interface MockAggregatorInterface {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import {AaveStrategy} from "./AaveStrategy.sol";
import {StripeSources} from "./StripeSources.sol";

import {IERC20, IFlashLoanReceiver, ICreditShaftCore} from "./interfaces/ISharedInterfaces.sol";

contract CreditShaftLeverage is
    Ownable,
    ReentrancyGuard,
    IFlashLoanReceiver,
    FunctionsClient,
    StripeSources,
    AutomationCompatibleInterface
{
    using FunctionsRequest for FunctionsRequest.Request;
    // Core addresses

    address public immutable creditShaftCore;
    AaveStrategy public aaveStrategy;
    IUniswapV2Router02 public immutable uniswapRouter;
    AggregatorV3Interface public immutable linkPriceFeed;

    IERC20 public immutable usdc;
    IERC20 public immutable link;

    // Chainlink Functions parameters
    bytes32 public donId;
    uint64 public donHostedSecretsVersion;
    uint64 public subscriptionId;
    uint32 public gasLimit = 300000;

    // Chainlink request tracking
    mapping(bytes32 => address) public requestIdToUser;

    // Position tracking
    // Note: preAuthAmount is stored in USDC format (6 decimals) and represents 150% of borrowed amount
    // When sending to Stripe, convert to cents: preAuthAmount / 10000 (6 decimals → 2 decimals)
    struct Position {
        uint256 collateralLINK; // User's initial LINK
        uint256 leverageRatio; // 2x, 3x, etc (scaled by 100)
        uint256 borrowedUSDC; // AAVE debt
        uint256 suppliedLINK; // Total LINK in AAVE
        uint256 entryPrice; // LINK price at entry
        uint256 preAuthAmount; // Card hold amount
        uint256 openTimestamp;
        uint256 preAuthExpiryTime; // When to charge pre-auth (PAYMENT ONLY - does NOT affect position)
        bool isActive; // Position can be traded/closed regardless of preAuth status
        bool preAuthCharged; // Track if pre-auth was charged (PAYMENT ONLY - does NOT affect position)
        string stripePaymentIntentId;
        string stripeCustomerId;
        string stripePaymentMethodId;
    }

    mapping(address => Position) public positions;
    uint256 public nextPositionId = 1;

    // Track active positions for efficient automation
    address[] public activeUsers;
    mapping(address => uint256) public userToActiveIndex; // 1-based index (0 means not active)

    // Protocol parameters
    uint256 public constant MAX_LEVERAGE = 500; // 5x max
    uint256 public constant MIN_LEVERAGE = 150; // 1.5x min
    uint256 public constant PREAUTH_MULTIPLIER = 150; // 150% of borrowed amount
    uint256 public constant LP_PROFIT_SHARE = 2000; // 20% of profits to LPs
    uint256 public constant SAFE_LTV = 6500;
    uint256 public constant PREAUTH_TIMEOUT = 7 days; // Charge pre-auth after 7 days

    // Automation tracking
    uint256 public automationCounter = 0;

    // Events
    event PositionOpened(address indexed user, uint256 leverage, uint256 collateral, uint256 totalExposure);
    event PositionClosed(address indexed user, uint256 profit, uint256 lpShare);
    event PreAuthCharged(address indexed user, uint256 amount);
    event PreAuthChargeInitiated(
        address indexed user, address indexed initiator, bytes32 indexed requestId, uint256 amount
    );
    event PreAuthChargeFailed(address indexed user, bytes32 indexed requestId, string reason);
    event StripeResponseReceived(address indexed user, bytes32 indexed requestId, string response);
    event AutomationExecuted(uint256 indexed counter, uint256 totalAttempts, uint256 successful, uint256 failed);

    constructor(
        address _creditShaftCore,
        address _aaveStrategy,
        address _uniswapRouter,
        address _linkPriceFeed,
        address _usdc,
        address _link,
        address _functionsRouter,
        bytes32 _donId,
        uint64 _donHostedSecretsVersion,
        uint64 _subscriptionId
    ) Ownable(msg.sender) FunctionsClient(_functionsRouter) {
        creditShaftCore = _creditShaftCore;
        if (_aaveStrategy != address(0)) {
            aaveStrategy = AaveStrategy(_aaveStrategy);
        }
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        linkPriceFeed = AggregatorV3Interface(_linkPriceFeed);
        usdc = IERC20(_usdc);
        link = IERC20(_link);
        donId = _donId;
        donHostedSecretsVersion = _donHostedSecretsVersion;
        subscriptionId = _subscriptionId;
    }

    // Main trading functions
    function openLeveragePosition(
        uint256 leverageRatio,
        uint256 collateralAmount,
        uint256 expiryTime,
        string memory stripePaymentIntentId,
        string memory stripeCustomerId,
        string memory stripePaymentMethodId
    ) external nonReentrant {
        require(collateralAmount > 0, "No LINK provided");
        require(leverageRatio >= MIN_LEVERAGE && leverageRatio <= MAX_LEVERAGE, "Invalid leverage");
        require(!positions[msg.sender].isActive, "Position already active");
        require(expiryTime > block.timestamp, "Expiry time must be in the future");

        // Transfer LINK from user
        link.transferFrom(msg.sender, address(this), collateralAmount);

        uint256 collateralLINK = collateralAmount;
        // For 2x leverage, we need to borrow 1x the collateral value in USD, not 1x the collateral LINK amount
        // borrowAmount should be in LINK tokens equivalent to the USD value we need to borrow
        uint256 leverageMultiplier = leverageRatio - 100; // 200 - 100 = 100 for 2x leverage
        uint256 borrowAmountLINK = (collateralLINK * leverageMultiplier) / 100;

        // Calculate and charge preAuth (done via Chainlink Functions in real implementation)
        uint256 linkPrice = getLINKPrice();
        require(linkPrice > 0, "Invalid LINK price");

        // Convert LINK collateral to USD value for borrowing
        uint256 collateralUSDValue = (collateralLINK * linkPrice) / 1e20; // LINK(18 decimals) * price(8 decimals) / 1e20 = USDC(6 decimals)
        uint256 borrowUSDValue = (collateralUSDValue * leverageMultiplier) / 100; // Amount to borrow in USD

        // Validate amounts to prevent overflow
        require(borrowAmountLINK > 0 && borrowAmountLINK <= type(uint128).max, "Invalid borrow amount");
        require(linkPrice <= type(uint128).max, "LINK price too high");
        require(borrowUSDValue > 0, "Calculated USD value is zero");
        require(borrowUSDValue <= type(uint128).max, "Borrow USD value too large");

        uint256 preAuthAmount = (borrowUSDValue * PREAUTH_MULTIPLIER) / 100;
        require(preAuthAmount > 0, "Pre-auth amount is zero");
        // Note: PreAuthCharged event is emitted only when actually charged via Stripe, not during position opening

        // Store position data
        positions[msg.sender] = Position({
            collateralLINK: collateralLINK,
            leverageRatio: leverageRatio,
            borrowedUSDC: 0, // Will be set after AAVE borrow
            suppliedLINK: 0, // Will be set after AAVE supply
            entryPrice: linkPrice,
            preAuthAmount: preAuthAmount,
            openTimestamp: block.timestamp,
            preAuthExpiryTime: expiryTime,
            isActive: true,
            preAuthCharged: false,
            stripePaymentIntentId: stripePaymentIntentId,
            stripeCustomerId: stripeCustomerId,
            stripePaymentMethodId: stripePaymentMethodId
        });

        nextPositionId++;

        // Add user to active positions list
        _addActiveUser(msg.sender);

        // Initiate flash loan to execute leverage
        bytes memory params = abi.encode(msg.sender, collateralLINK, borrowAmountLINK, false);
        ICreditShaftCore(creditShaftCore).provideFlashLoan(address(this), address(usdc), borrowUSDValue, params);
    }

    function closeLeveragePosition() external nonReentrant {
        Position storage pos = positions[msg.sender];
        require(pos.isActive, "No active position");

        // NOTE: Position can be closed regardless of preAuth expiry/charge status
        // preAuthExpiryTime and preAuthCharged only affect payment processing, not position management

        // Initiate flash loan to unwind position
        bytes memory params = abi.encode(msg.sender, pos.borrowedUSDC, 0, true);
        ICreditShaftCore(creditShaftCore).provideFlashLoan(address(this), address(usdc), pos.borrowedUSDC, params);
    }

    // Flash loan callback
    function executeOperation(
        address[] calldata, /* assets */
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == creditShaftCore, "Invalid caller");
        require(initiator == address(this), "Invalid initiator");

        (address user,,, bool isClosing) = abi.decode(params, (address, uint256, uint256, bool));

        if (!isClosing) {
            _executeOpenPosition(user, amounts[0]);
        } else {
            _executeClosePosition(user, amounts[0]);
        }

        // Approve repayment
        uint256 repayAmount = amounts[0] + premiums[0];
        usdc.approve(creditShaftCore, repayAmount);

        return true;
    }

    // --- THE   OPEN POSITION FUNCTION ---
    function _executeOpenPosition(address user, uint256 flashLoanAmount) internal {
        Position storage pos = positions[user];

        // 1. Swap USDC to LINK
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(link);

        usdc.approve(address(uniswapRouter), flashLoanAmount);
        uint256[] memory amounts =
            uniswapRouter.swapExactTokensForTokens(flashLoanAmount, 0, path, address(this), block.timestamp);
        uint256 borrowedLINK = amounts[1];

        // 2. Supply total LINK to Aave via the Strategy contract
        uint256 totalLINK = pos.collateralLINK + borrowedLINK;
        link.approve(address(aaveStrategy), totalLINK);
        // The strategy now handles making itself the owner in Aave
        aaveStrategy.supply(address(link), totalLINK);

        // 3. Calculate repay amount
        uint256 flashLoanPremium = (flashLoanAmount * 9) / 10000;
        uint256 totalRepayAmount = flashLoanAmount + flashLoanPremium;

        aaveStrategy.borrow(address(usdc), totalRepayAmount);

        // 6. Update position
        pos.borrowedUSDC = totalRepayAmount;
        pos.suppliedLINK = totalLINK;

        emit PositionOpened(user, pos.leverageRatio, pos.collateralLINK, totalLINK);
    }

    function _executeClosePosition(address user, uint256 flashLoanAmount) internal {
        Position storage pos = positions[user];

        // 1. Repay AAVE debt using the flash-loaned USDC.
        usdc.approve(address(aaveStrategy), pos.borrowedUSDC);
        aaveStrategy.repay(address(usdc), pos.borrowedUSDC);

        // 2. Withdraw ALL BUT 1 WEI of LINK collateral from the strategy contract's Aave position.
        // This is the CRITICAL FIX to avoid Aave's health factor validation error (revert 35).
        uint256 amountToWithdraw = pos.suppliedLINK - 1; // Leave 1 wei of dust
        uint256 withdrawnAmountLINK = aaveStrategy.withdraw(address(link), amountToWithdraw);
        require(withdrawnAmountLINK > 0, "Aave withdraw failed");

        // 3. Swap just enough LINK to repay the flash loan + premium.
        uint256 flashLoanPremium = (flashLoanAmount * 9) / 10000;
        uint256 totalRepayUSDC = flashLoanAmount + flashLoanPremium;

        address[] memory path = new address[](2);
        path[0] = address(link);
        path[1] = address(usdc);

        uint256[] memory requiredLINKAmounts = uniswapRouter.getAmountsIn(totalRepayUSDC, path);
        uint256 linkToSwap = requiredLINKAmounts[0];
        require(withdrawnAmountLINK >= linkToSwap, "Not enough LINK to repay flash loan");

        link.approve(address(uniswapRouter), linkToSwap);
        uniswapRouter.swapExactTokensForTokens(linkToSwap, totalRepayUSDC, path, address(this), block.timestamp);

        // 4. Calculate and distribute profits.
        uint256 remainingLINK = withdrawnAmountLINK - linkToSwap;

        uint256 profitLINK = 0;
        if (remainingLINK > pos.collateralLINK) {
            profitLINK = remainingLINK - pos.collateralLINK;
        }

        if (profitLINK > 0) {
            uint256 lpShareLINK = (profitLINK * LP_PROFIT_SHARE) / 10000;
            uint256 userShareLINK = profitLINK - lpShareLINK;

            if (lpShareLINK > 0) {
                link.approve(address(uniswapRouter), lpShareLINK);
                uint256[] memory amountsOut =
                    uniswapRouter.swapExactTokensForTokens(lpShareLINK, 0, path, address(this), block.timestamp);
                _distributeLPProfits(amountsOut[1]);
            }
            link.transfer(user, pos.collateralLINK + userShareLINK);
            emit PositionClosed(user, userShareLINK, lpShareLINK);
        } else {
            if (remainingLINK > 0) {
                link.transfer(user, remainingLINK);
            }
            emit PositionClosed(user, 0, 0);
        }

        // 5. Clean up state.
        _removeActiveUser(user);
        delete positions[user];
    }

    function _distributeLPProfits(uint256 usdcAmount) internal {
        if (usdcAmount == 0) return;

        // Send USDC rewards to CreditShaftCore to distribute to flash loan LPs
        usdc.transfer(creditShaftCore, usdcAmount);
        ICreditShaftCore(creditShaftCore).receiveRewards(usdcAmount);
    }

    function getLINKPrice() public view returns (uint256) {
        int256 price = MockAggregatorInterface(address(linkPriceFeed)).latestAnswer();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    /**
     * @notice Public function to charge expired PreAuth for any user
     * @dev Anyone can call this to trigger PreAuth charging for expired positions
     * @param user Address of the user whose PreAuth should be charged
     */
    function chargeExpiredPreAuth(address user) external {
        _chargeExpiredPreAuth(user);
    }

    /**
     * @notice Check if a position is ready for PreAuth charging
     * @param user Address of the user to check
     * @return ready True if the position can be charged
     */
    function isReadyForPreAuthCharge(address user) external view returns (bool ready) {
        Position storage pos = positions[user];
        return pos.isActive && !pos.preAuthCharged && block.timestamp >= pos.preAuthExpiryTime;
    }


    // Chainlink Functions integration

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        address user = requestIdToUser[requestId];
        require(user != address(0), "Invalid request ID");

        Position storage pos = positions[user];

        // Handle error cases
        if (err.length > 0) {
            emit PreAuthChargeFailed(user, requestId, string(err));
            delete requestIdToUser[requestId];
            return;
        }

        // Parse Stripe response
        if (response.length > 0) {
            // Debug: Log the raw response
            emit StripeResponseReceived(user, requestId, string(response));
            
            try this.parseStripeResponse(response) returns (bool success, string memory /* status */) {
                if (success) {
                    // Successfully charged - mark as charged
                    pos.preAuthCharged = true;
                    emit PreAuthCharged(user, pos.preAuthAmount);
                } else {
                    // Charge failed
                    emit PreAuthChargeFailed(user, requestId, "Stripe charge failed");
                }
            } catch {
                // Failed to parse response
                emit PreAuthChargeFailed(user, requestId, "Failed to parse Stripe response");
            }
        } else {
            emit PreAuthChargeFailed(user, requestId, "Empty response from Stripe");
        }

        // Clean up the mapping
        delete requestIdToUser[requestId];
    }

    /**
     * @notice Parse Stripe API response from Chainlink Functions - Simplified Version
     * @dev External function to allow try/catch in fulfillRequest
     * @param response Raw response bytes from Chainlink Functions
     * @return success Whether the charge was successful
     * @return status Simple status indicator
     */
    function parseStripeResponse(bytes memory response) external pure returns (bool success, string memory status) {
        // Expected success format: {"success":true,"paymentIntentId":"pi_xxx","status":"succeeded","amountCaptured":1000,"currency":"usd"}
        
        string memory responseStr = string(response);
        
        // Simple checks for success case
        bool hasSuccessTrue = _contains(responseStr, '"success":true');
        bool hasStatusSucceeded = _contains(responseStr, '"status":"succeeded"');
        
        // Must have both conditions for success
        success = hasSuccessTrue && hasStatusSucceeded;
        
        // Return simple status
        if (success) {
            status = "succeeded";
        } else {
            status = "failed";
        }
        
        return (success, status);
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /**
     * @notice Check if a string contains a substring
     * @param str The string to search in
     * @param substr The substring to search for
     * @return True if substr is found in str
     */
    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Extract a JSON value after a given key
     * @param json The JSON string
     * @param key The key to search for (including quotes and colon)
     * @return The extracted value (without quotes)
     */
    function _extractJsonValue(string memory json, string memory key) internal pure returns (string memory) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(key);

        // Find the key
        for (uint256 i = 0; i <= jsonBytes.length - keyBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < keyBytes.length; j++) {
                if (jsonBytes[i + j] != keyBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                // Found the key, now extract the value
                uint256 valueStart = i + keyBytes.length;
                if (valueStart < jsonBytes.length && jsonBytes[valueStart] == '"') {
                    valueStart++; // Skip opening quote
                    uint256 valueEnd = valueStart;
                    while (valueEnd < jsonBytes.length && jsonBytes[valueEnd] != '"') {
                        valueEnd++;
                    }
                    // Extract the value without quotes
                    bytes memory value = new bytes(valueEnd - valueStart);
                    for (uint256 k = 0; k < valueEnd - valueStart; k++) {
                        value[k] = jsonBytes[valueStart + k];
                    }
                    return string(value);
                }
            }
        }
        return "";
    }

    // Chainlink Automation to charge expired PreAuths
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Find positions with expired PreAuths that need charging
        address[] memory usersToCharge = new address[](20); // Max 20 users per upkeep
        uint256 count = 0;
        
        // Scan through active users (limit to prevent gas issues)
        uint256 maxCheck = activeUsers.length > 50 ? 50 : activeUsers.length;
        
        for (uint256 i = 0; i < maxCheck && count < 20; i++) {
            address user = activeUsers[i];
            Position storage pos = positions[user];
            
            // Check if position needs PreAuth charging
            if (pos.isActive && 
                !pos.preAuthCharged && 
                block.timestamp >= pos.preAuthExpiryTime) {
                usersToCharge[count] = user;
                count++;
            }
        }
        
        upkeepNeeded = count > 0;
        performData = abi.encode(usersToCharge, count);
    }

    function performUpkeep(bytes calldata performData) external override {
        // Charge expired PreAuths
        (address[] memory usersToCharge, uint256 count) = abi.decode(performData, (address[], uint256));
        
        uint256 successfulCharges = 0;
        uint256 failedCharges = 0;
        
        for (uint256 i = 0; i < count; i++) {
            address user = usersToCharge[i];
            try this.chargeExpiredPreAuth(user) {
                successfulCharges++;
            } catch {
                failedCharges++;
                // Continue with other users even if one fails
            }
        }
        
        // Update automation stats
        automationCounter++;
        
        // Emit event with automation results
        emit AutomationExecuted(automationCounter, count, successfulCharges, failedCharges);
    }

    function _chargeExpiredPreAuth(address user) internal {
        Position storage pos = positions[user];
        require(pos.isActive, "Position not active");
        require(!pos.preAuthCharged, "Pre-auth already charged");
        require(block.timestamp >= pos.preAuthExpiryTime, "Pre-auth not expired");

        // NOTE: This only affects payment processing, NOT position functionality
        // Position remains active and tradeable even after preAuth is charged

        // Create Chainlink Functions request to charge Stripe PreAuth
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getStripeChargeSource());
        req.addDONHostedSecrets(0, donHostedSecretsVersion);

        // Pass payment intent ID and amount to charge
        // Convert preAuthAmount from USDC format (6 decimals) to Stripe cents (2 decimals)
        string[] memory args = new string[](2);
        args[0] = pos.stripePaymentIntentId;
        args[1] = _uint2str(pos.preAuthAmount / 10000); // USDC (6 decimals) → cents (2 decimals)
        req.setArgs(args);

        // Send the request
        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        requestIdToUser[requestId] = user;

        // Emit event for tracking
        emit PreAuthChargeInitiated(user, msg.sender, requestId, pos.preAuthAmount);
    }

    // Internal helper functions for active user tracking
    function _addActiveUser(address user) internal {
        if (userToActiveIndex[user] == 0) {
            // Not already in list
            activeUsers.push(user);
            userToActiveIndex[user] = activeUsers.length; // 1-based index
        }
    }

    function _removeActiveUser(address user) internal {
        uint256 index = userToActiveIndex[user];
        if (index > 0) {
            // User is in the list
            uint256 arrayIndex = index - 1; // Convert to 0-based
            uint256 lastIndex = activeUsers.length - 1;

            if (arrayIndex != lastIndex) {
                // Move last user to the position of removed user
                address lastUser = activeUsers[lastIndex];
                activeUsers[arrayIndex] = lastUser;
                userToActiveIndex[lastUser] = index; // Update index for moved user
            }

            // Remove last element and clear mapping
            activeUsers.pop();
            userToActiveIndex[user] = 0;
        }
    }

    // Admin functions
    function setAaveStrategy(address _aaveStrategy) external onlyOwner {
        require(_aaveStrategy != address(0), "Invalid address");
        aaveStrategy = AaveStrategy(_aaveStrategy);
    }

    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        // Implementation for emergency withdrawal
    }
}
