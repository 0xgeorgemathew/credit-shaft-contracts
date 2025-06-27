// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/CreditShaftLeverage.sol";
import {IERC20} from "../src/interfaces/ISharedInterfaces.sol";

/**
 * @title OpenPosition
 * @notice A script to test opening a leveraged position with human-readable output.
 */
contract OpenPosition is Script {
    // --- Configuration ---
    uint256 constant LEVERAGE_RATIO = 200; // 2x leverage
    uint256 constant COLLATERAL_AMOUNT = 0.1e18; // 0.1 LINK
    uint256 constant EXPIRY_DURATION = 1 minutes; // 1 day from now
    uint256 constant LINK_DECIMALS = 18;
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant PRICE_FEED_DECIMALS = 8;

    // Mock Stripe data
    string constant MOCK_PAYMENT_INTENT_ID = "pi_3RebPh3PrM4sdLLb1PUhh3bV";
    string constant MOCK_CUSTOMER_ID = "pi_3RebPh3PrM4sdLLb1PUhh3bV";
    string constant MOCK_PAYMENT_METHOD_ID = "pi_3RebPh3PrM4sdLLb1PUhh3bV";

    // --- State Variables ---
    address creditShaftLeverageAddress;
    address linkTokenAddress;
    CreditShaftLeverage leverageContract;
    IERC20 link;

    function run() external {
        _loadDeploymentAddresses();

        address deployer = msg.sender;
        leverageContract = CreditShaftLeverage(creditShaftLeverageAddress);
        link = IERC20(linkTokenAddress);

        console.log("\n=====================================");
        console.log(unicode"  🚀 Running OpenPosition Script 🚀   ");
        console.log("=====================================");

        // --- 1. Configuration & Pre-flight Checks ---
        console.log(unicode"\n📋 --- 1. Configuration & Pre-flight Checks --- 📋");
        console.log("Executor Address:            ", deployer);
        console.log("CreditShaftLeverage Contract:", creditShaftLeverageAddress);
        console.log("Collateral to Provide:       %s LINK", _formatAmount(COLLATERAL_AMOUNT, LINK_DECIMALS, 4));
        console.log("Desired Leverage:            %dx", LEVERAGE_RATIO / 100);
        console.log("PreAuth Expiry Duration:     %d seconds (%d days)", EXPIRY_DURATION, EXPIRY_DURATION / 1 days);

        uint256 initialLinkBalance = link.balanceOf(deployer);
        console.log("Current LINK Balance:        %s LINK", _formatAmount(initialLinkBalance, LINK_DECIMALS, 4));
        require(initialLinkBalance >= COLLATERAL_AMOUNT, "Error: Insufficient LINK balance.");

        (,,,,,,,, bool pre_tx_isActive,,,,) = leverageContract.positions(deployer);
        require(!pre_tx_isActive, "Error: An active position already exists. Please close it first.");
        console.log(unicode"✅ Checks Passed: Sufficient balance and no active position.");

        // --- 2. Execution ---
        console.log(unicode"\n⚙️ --- 2. Execution --- ⚙️");
        vm.startBroadcast();

        console.log("   - Approving LINK for spending...");
        link.approve(creditShaftLeverageAddress, COLLATERAL_AMOUNT);

        console.log("   - Calling openLeveragePosition()...");
        uint256 expiryTime = block.timestamp + EXPIRY_DURATION;
        leverageContract.openLeveragePosition(
            LEVERAGE_RATIO,
            COLLATERAL_AMOUNT,
            expiryTime,
            MOCK_PAYMENT_INTENT_ID,
            MOCK_CUSTOMER_ID,
            MOCK_PAYMENT_METHOD_ID
        );

        vm.stopBroadcast();
        console.log(unicode"✅ Transaction successful!");

        // --- 3. Verification & Final State ---
        console.log(unicode"\n📊 --- 3. Verification & Final State --- 📊");

        // Unpack the tuple returned from the external call
        (
            uint256 collateralLINK,
            uint256 leverageRatio,
            uint256 borrowedUSDC,
            uint256 suppliedLINK,
            uint256 entryPriceRaw,
            ,
            ,
            ,
            bool positionActive,
            ,
            ,
            ,
            string memory stripePaymentMethodId
        ) = leverageContract.positions(deployer);

        // NOW use the unpacked variables for verification
        require(positionActive, "Verification FAILED: Position is not marked as active.");
        console.log(unicode"✅ Position is active on-chain.");
        require(
            keccak256(bytes(stripePaymentMethodId)) == keccak256(bytes(MOCK_PAYMENT_METHOD_ID)),
            "Verification FAILED: Stripe data mismatch."
        );

        uint256 linkPrice = leverageContract.getLINKPrice();
        uint256 collateralValueUSD =
            (collateralLINK * linkPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));
        uint256 totalExposureUSD =
            (suppliedLINK * linkPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));

        console.log("\n=== Position Details (Human-Readable) ===");
        console.log("  - Entry Price:           $%s", _formatAmount(entryPriceRaw, PRICE_FEED_DECIMALS, 2));
        console.log("  - Initial Collateral:    %s LINK", _formatAmount(collateralLINK, LINK_DECIMALS, 4));
        console.log("  - Collateral Value:      $%s", _formatAmount(collateralValueUSD, USDC_DECIMALS, 2));
        console.log("  - Leverage Ratio:        %d%%", leverageRatio);
        console.log("-------------------------------------------");
        console.log("  - Total LINK Supplied:   %s LINK", _formatAmount(suppliedLINK, LINK_DECIMALS, 4));
        console.log("  - Total Exposure:        $%s", _formatAmount(totalExposureUSD, USDC_DECIMALS, 2));
        console.log("  - Aave Debt:             %s USDC", _formatAmount(borrowedUSDC, USDC_DECIMALS, 2));

        uint256 finalLinkBalance = link.balanceOf(deployer);
        console.log("\n=== Wallet Balance Change ===");
        console.log(
            "  - LINK transferred:      %s LINK", _formatAmount(initialLinkBalance - finalLinkBalance, LINK_DECIMALS, 4)
        );
        console.log("  - Final wallet balance:  %s LINK", _formatAmount(finalLinkBalance, LINK_DECIMALS, 4));

        console.log("\n=====================================");
        console.log(unicode"        🎉 Test Complete 🎉         ");
        console.log("=====================================");
    }

    /**
     * @dev Helper function to format a uint256 amount into a human-readable decimal string.
     */
    function _formatAmount(uint256 amount, uint256 decimals, uint256 displayDecimals)
        internal
        pure
        returns (string memory)
    {
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = amount / divisor;

        if (displayDecimals == 0) {
            return vm.toString(integerPart);
        }

        uint256 displayDivisor = 10 ** displayDecimals;
        uint256 fractionalPart = (amount * displayDivisor / divisor) % displayDivisor;

        string memory fractionalString = vm.toString(fractionalPart);
        if (bytes(fractionalString).length < displayDecimals) {
            string memory padding = "";
            uint256 requiredPadding = displayDecimals - bytes(fractionalString).length;
            for (uint256 i = 0; i < requiredPadding; i++) {
                padding = string.concat(padding, "0");
            }
            fractionalString = string.concat(padding, fractionalString);
        }

        return string.concat(vm.toString(integerPart), ".", fractionalString);
    }

    function _loadDeploymentAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/sepolia.json");
        string memory json = vm.readFile(path);
        creditShaftLeverageAddress = vm.parseJsonAddress(json, ".contracts.CreditShaftLeverage");
        linkTokenAddress = vm.parseJsonAddress(json, ".dependencies.LINK");
        require(creditShaftLeverageAddress != address(0), "Failed to load CreditShaftLeverage address.");
        require(linkTokenAddress != address(0), "Failed to load LINK token address.");
    }
}
