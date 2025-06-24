// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftLeverage.sol";
import {IERC20 as IERC20Standard} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestOpenLeveragePosition
 * @dev Script to test calling openLeveragePosition() on deployed Sepolia contract
 *
 * USAGE:
 * 1. Ensure you have LINK tokens in your deployer account
 * 2. Run: forge script script/TestOpenLeveragePosition.s.sol --rpc-url $SEPOLIA_RPC_URL --account deployerKey --broadcast
 *
 * REQUIREMENTS:
 * - Deployer account must have LINK tokens (get from Sepolia faucet)
 * - Contract must be deployed and address must match deployment
 * - Sufficient ETH for gas fees
 */
contract TestOpenLeveragePosition is Script {
    // Test parameters
    uint256 constant TEST_LEVERAGE_RATIO = 200; // 2x leverage
    uint256 constant TEST_COLLATERAL_AMOUNT = 1e18; // 1 LINK token

    // Mock Stripe parameters for testing
    string constant MOCK_PAYMENT_INTENT_ID = "pi_test_1234567890abcdef";
    string constant MOCK_CUSTOMER_ID = "cus_test_customer123";
    string constant MOCK_PAYMENT_METHOD_ID = "pm_test_payment_method456";
    
    // Loaded from JSON
    address public creditShaftLeverage;
    address public linkToken;

    function run() external {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        
        // Load deployment addresses from JSON file
        _loadDeploymentAddresses();

        vm.startBroadcast();

        // Get contract instances
        CreditShaftLeverage leverageContract = CreditShaftLeverage(creditShaftLeverage);
        IERC20Standard linkTokenContract = IERC20Standard(linkToken);

        console.log("=== Testing openLeveragePosition() ===");
        console.log("Deployer address:", deployerAddress);
        console.log("CreditShaftLeverage contract:", creditShaftLeverage);
        console.log("LINK token:", linkToken);

        // Check current LINK balance
        uint256 linkBalance = linkTokenContract.balanceOf(deployerAddress);
        console.log("Current LINK balance:", linkBalance);

        require(linkBalance >= TEST_COLLATERAL_AMOUNT, "Insufficient LINK balance - get tokens from Sepolia faucet");

        // Check if user already has an active position
        (,,,,,,,, bool hasActivePosition,,,,) = leverageContract.positions(deployerAddress);
        require(!hasActivePosition, "Position already active - close existing position first");

        // Approve LINK spending
        console.log("Approving LINK token spending...");
        linkTokenContract.approve(creditShaftLeverage, TEST_COLLATERAL_AMOUNT);

        // Check allowance
        uint256 allowance = linkTokenContract.allowance(deployerAddress, creditShaftLeverage);
        console.log("LINK allowance granted:", allowance);
        require(allowance >= TEST_COLLATERAL_AMOUNT, "Failed to approve LINK spending");

        console.log("=== Opening Leverage Position ===");
        console.log("Leverage ratio:", TEST_LEVERAGE_RATIO, "(2x)");
        console.log("Collateral amount:", TEST_COLLATERAL_AMOUNT, "LINK");
        console.log("Payment Intent ID:", MOCK_PAYMENT_INTENT_ID);
        console.log("Customer ID:", MOCK_CUSTOMER_ID);
        console.log("Payment Method ID:", MOCK_PAYMENT_METHOD_ID);

        // Call openLeveragePosition
        try leverageContract.openLeveragePosition(
            TEST_LEVERAGE_RATIO,
            TEST_COLLATERAL_AMOUNT,
            MOCK_PAYMENT_INTENT_ID,
            MOCK_CUSTOMER_ID,
            MOCK_PAYMENT_METHOD_ID
        ) {
            console.log("Position opened successfully!");

            // Check position details
            (
                uint256 collateralLINK,
                uint256 leverageRatio,
                uint256 borrowedUSDC,
                uint256 suppliedLINK,
                uint256 entryPrice,
                uint256 preAuthAmount,
                uint256 openTimestamp,
                uint256 preAuthExpiryTime,
                bool positionActive,
                bool preAuthCharged,
                string memory stripePaymentIntentId,
                string memory stripeCustomerId,
                string memory stripePaymentMethodId
            ) = leverageContract.positions(deployerAddress);

            console.log("=== Position Details ===");
            console.log("Collateral LINK:", collateralLINK);
            console.log("Leverage ratio:", leverageRatio);
            console.log("Borrowed USDC:", borrowedUSDC);
            console.log("Supplied LINK:", suppliedLINK);
            console.log("Entry price:", entryPrice);
            console.log("Pre-auth amount:", preAuthAmount);
            console.log("Open timestamp:", openTimestamp);
            console.log("Pre-auth expiry time:", preAuthExpiryTime);
            console.log("Is active:", positionActive);
            console.log("Pre-auth charged:", preAuthCharged);
            console.log("Stripe Payment Intent ID:", stripePaymentIntentId);
            console.log("Stripe Customer ID:", stripeCustomerId);
            console.log("Stripe Payment Method ID:", stripePaymentMethodId);
        } catch Error(string memory reason) {
            console.log(" Transaction failed with reason:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("Transaction failed with low-level error");
            console.logBytes(lowLevelData);
            revert("Low-level call failed");
        }

        // Check final LINK balance
        uint256 finalLinkBalance = linkTokenContract.balanceOf(deployerAddress);
        console.log("Final LINK balance:", finalLinkBalance);
        console.log("LINK spent:", linkBalance - finalLinkBalance);

        vm.stopBroadcast();

        console.log("=== Test Complete ===");
        console.log("Position opened successfully!");
        console.log("You can now test closing the position or wait for pre-auth timeout");
    }
    
    function _loadDeploymentAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/sepolia.json");
        string memory json = vm.readFile(path);
        
        creditShaftLeverage = vm.parseJsonAddress(json, ".contracts.CreditShaftLeverage");
        linkToken = vm.parseJsonAddress(json, ".dependencies.LINK");
        
        console.log("Loaded from JSON:");
        console.log("  CreditShaftLeverage:", creditShaftLeverage);
        console.log("  LINK Token:", linkToken);
    }
}
