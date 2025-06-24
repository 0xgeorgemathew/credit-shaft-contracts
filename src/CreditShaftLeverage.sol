// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IUniswapV2Router02} from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
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
    struct Position {
        uint256 collateralLINK; // User's initial LINK
        uint256 leverageRatio; // 2x, 3x, etc (scaled by 100)
        uint256 borrowedUSDC; // AAVE debt
        uint256 suppliedLINK; // Total LINK in AAVE
        uint256 entryPrice; // LINK price at entry
        uint256 preAuthAmount; // Card hold amount
        uint256 openTimestamp;
        uint256 preAuthExpiryTime; // When to charge pre-auth
        bool isActive;
        bool preAuthCharged; // Track if pre-auth was charged
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
    uint256 public constant SAFE_LTV = 5000; // 50% LTV for safety
    uint256 public constant PREAUTH_TIMEOUT = 7 days; // Charge pre-auth after 7 days

    // Events
    event PositionOpened(address indexed user, uint256 leverage, uint256 collateral, uint256 totalExposure);
    event PositionClosed(address indexed user, uint256 profit, uint256 lpShare);
    event PreAuthCharged(address indexed user, uint256 amount);

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
        string memory stripePaymentIntentId,
        string memory stripeCustomerId,
        string memory stripePaymentMethodId
    ) external nonReentrant {
        require(collateralAmount > 0, "No LINK provided");
        require(leverageRatio >= MIN_LEVERAGE && leverageRatio <= MAX_LEVERAGE, "Invalid leverage");
        require(!positions[msg.sender].isActive, "Position already active");

        // Transfer LINK from user
        link.transferFrom(msg.sender, address(this), collateralAmount);

        uint256 collateralLINK = collateralAmount;
        uint256 borrowAmount = (collateralLINK * (leverageRatio - 100)) / 100;

        // Calculate and charge preAuth (done via Chainlink Functions in real implementation)
        uint256 linkPrice = getLINKPrice();
        uint256 borrowUSDValue = (borrowAmount * linkPrice) / 1e18;
        uint256 preAuthAmount = (borrowUSDValue * PREAUTH_MULTIPLIER) / 100;
        emit PreAuthCharged(msg.sender, preAuthAmount);

        // Store position data
        positions[msg.sender] = Position({
            collateralLINK: collateralLINK,
            leverageRatio: leverageRatio,
            borrowedUSDC: 0, // Will be set after AAVE borrow
            suppliedLINK: 0, // Will be set after AAVE supply
            entryPrice: linkPrice,
            preAuthAmount: preAuthAmount,
            openTimestamp: block.timestamp,
            preAuthExpiryTime: block.timestamp + PREAUTH_TIMEOUT,
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
        bytes memory params = abi.encode(msg.sender, collateralLINK, borrowAmount, false);
        ICreditShaftCore(creditShaftCore).provideFlashLoan(address(this), address(usdc), borrowUSDValue, params);
    }

    function closeLeveragePosition() external nonReentrant {
        Position storage pos = positions[msg.sender];
        require(pos.isActive, "No active position");

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
        require(initiator == creditShaftCore, "Invalid initiator");

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

    function _executeOpenPosition(address user, uint256 flashLoanAmount) internal {
        Position storage pos = positions[user];

        // 1. Swap USDC to LINK
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(link);

        usdc.approve(address(uniswapRouter), flashLoanAmount);
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            flashLoanAmount,
            0, // Accept any amount of LINK
            path,
            address(this),
            block.timestamp
        );
        uint256 borrowedLINK = amounts[1];

        // 2. Supply total LINK to AAVE
        uint256 totalLINK = pos.collateralLINK + borrowedLINK;
        link.transfer(address(aaveStrategy), totalLINK);
        aaveStrategy.supply(address(link), totalLINK, user);

        // 3. Borrow USDC from AAVE to repay flash loan
        // We need to borrow enough to repay the flash loan + premium
        uint256 flashLoanPremium = (flashLoanAmount * 9) / 10000; // 0.09% fee (same as CreditShaftCore)
        uint256 totalRepayAmount = flashLoanAmount + flashLoanPremium;

        // Safety check: ensure we don't exceed safe LTV
        uint256 maxBorrowAmount = (totalLINK * getLINKPrice() * SAFE_LTV) / (100 * 1e18);
        require(totalRepayAmount <= maxBorrowAmount, "Leverage too high for safe LTV");

        aaveStrategy.borrow(address(usdc), totalRepayAmount, user);

        // Store actual borrowed amount for position tracking
        uint256 borrowUSDC = totalRepayAmount;

        // Update position
        pos.borrowedUSDC = borrowUSDC;
        pos.suppliedLINK = totalLINK;

        emit PositionOpened(user, pos.leverageRatio, pos.collateralLINK, totalLINK);
    }

    function _executeClosePosition(address user, uint256 flashLoanAmount) internal {
        Position storage pos = positions[user];

        // 1. Repay AAVE debt
        usdc.transfer(address(aaveStrategy), pos.borrowedUSDC);
        aaveStrategy.repay(address(usdc), pos.borrowedUSDC, user);

        // 2. Withdraw LINK from AAVE
        aaveStrategy.withdraw(address(link), type(uint256).max, address(this));

        // 3. Calculate profit
        uint256 currentLINKPrice = getLINKPrice();

        // 4. Swap enough LINK to repay flash loan
        require(currentLINKPrice > 0, "Invalid LINK price");
        uint256 linkNeededForRepay = (flashLoanAmount * 1e18) / currentLINKPrice;
        require(linkNeededForRepay > 0, "Invalid swap amount");

        address[] memory path = new address[](2);
        path[0] = address(link);
        path[1] = address(usdc);

        link.approve(address(uniswapRouter), linkNeededForRepay);
        uniswapRouter.swapExactTokensForTokens(
            linkNeededForRepay, flashLoanAmount, path, address(this), block.timestamp
        );

        // 5. Calculate and distribute profits
        uint256 remainingLINK = link.balanceOf(address(this));
        uint256 profit = remainingLINK > pos.collateralLINK ? remainingLINK - pos.collateralLINK : 0;

        if (profit > 0) {
            uint256 lpShare = (profit * LP_PROFIT_SHARE) / 10000;
            uint256 userShare = profit - lpShare;

            // Convert LP share to USDC and distribute
            link.approve(address(uniswapRouter), lpShare);
            uint256[] memory amounts =
                uniswapRouter.swapExactTokensForTokens(lpShare, 0, path, address(this), block.timestamp);

            // Distribute to LPs proportionally
            _distributeLPProfits(amounts[1]);

            // Send remaining LINK to user
            link.transfer(user, pos.collateralLINK + userShare);

            emit PositionClosed(user, userShare, lpShare);
        } else {
            // Return whatever is left to user
            link.transfer(user, remainingLINK);
            emit PositionClosed(user, 0, 0);
        }

        // Release preAuth via Chainlink Functions
        _releasePreAuth(user);

        // Remove user from active list
        _removeActiveUser(user);

        // Clear position
        delete positions[user];
    }

    function _distributeLPProfits(uint256 usdcAmount) internal {
        if (usdcAmount == 0) return;

        // Send USDC rewards to CreditShaftCore to distribute to flash loan LPs
        usdc.transfer(creditShaftCore, usdcAmount);
        ICreditShaftCore(creditShaftCore).receiveRewards(usdcAmount);
    }

    function getLINKPrice() public view returns (uint256) {
        (, int256 price,,,) = linkPriceFeed.latestRoundData();
        return uint256(price) * 1e10; // Chainlink returns 8 decimals
    }

    // Chainlink Functions integration
    function _chargePreAuth(address user) internal {
        Position storage pos = positions[user];
        require(pos.isActive, "Position not active");

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getStripeChargeSource());
        req.addDONHostedSecrets(0, donHostedSecretsVersion);

        string[] memory args = new string[](2);
        args[0] = pos.stripePaymentIntentId;
        args[1] = _uint2str(pos.preAuthAmount);
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        requestIdToUser[requestId] = user;
    }

    function _releasePreAuth(address user) internal {
        Position storage pos = positions[user];

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getStripeReleaseSource());
        req.addDONHostedSecrets(0, donHostedSecretsVersion);

        string[] memory args = new string[](1);
        args[0] = pos.stripePaymentIntentId;
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        requestIdToUser[requestId] = user;
    }

    function fulfillRequest(bytes32 requestId, bytes memory, /* response */ bytes memory err) internal override {
        // Handle the response from Chainlink Functions
        if (err.length > 0) {
            // Handle error
            return;
        }

        // Parse response and handle accordingly
        // For now, just clean up the mapping
        delete requestIdToUser[requestId];
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

    // Chainlink Automation for pre-auth timeout charging
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory usersToCharge = new address[](100); // Max 100 per batch
        uint256 count = 0;

        // Check active users for expired pre-auths
        for (uint256 i = 0; i < activeUsers.length && count < 100; i++) {
            address user = activeUsers[i];
            Position storage pos = positions[user];

            if (pos.isActive && !pos.preAuthCharged && block.timestamp >= pos.preAuthExpiryTime) {
                usersToCharge[count] = user;
                count++;
            }
        }

        upkeepNeeded = count > 0;
        performData = abi.encode(usersToCharge, count);
    }

    function performUpkeep(bytes calldata performData) external override {
        (address[] memory usersToCharge, uint256 count) = abi.decode(performData, (address[], uint256));

        for (uint256 i = 0; i < count; i++) {
            _chargeExpiredPreAuth(usersToCharge[i]);
        }
    }

    function _chargeExpiredPreAuth(address user) internal {
        Position storage pos = positions[user];
        require(pos.isActive, "Position not active");
        require(!pos.preAuthCharged, "Pre-auth already charged");
        require(block.timestamp >= pos.preAuthExpiryTime, "Pre-auth not expired");

        pos.preAuthCharged = true;

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getStripeChargeSource());
        req.addDONHostedSecrets(0, donHostedSecretsVersion);

        string[] memory args = new string[](2);
        args[0] = pos.stripePaymentIntentId;
        args[1] = _uint2str(pos.preAuthAmount);
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        requestIdToUser[requestId] = user;

        emit PreAuthCharged(user, pos.preAuthAmount);
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
