// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/CreditShaftLeverage.sol";
import {IERC20} from "../src/interfaces/ISharedInterfaces.sol";

/**
 * @title ClosePosition
 * @notice A script to test closing an active leveraged position with human-readable output.
 */
contract ClosePosition is Script {
    // --- Configuration ---
    uint256 constant LINK_DECIMALS = 18;
    uint256 constant USDC_DECIMALS = 6;

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
        console.log(unicode"  🔒 Running ClosePosition Script 🔒   ");
        console.log("=====================================");

        // --- 1. Verifying Active Position ---
        console.log(unicode"\n📋 --- 1. Verifying Active Position --- 📋");
        console.log("Executor Address:            ", deployer);
        console.log("CreditShaftLeverage Contract:", creditShaftLeverageAddress);

        uint256 initialLinkBalance = link.balanceOf(deployer);

        (uint256 collateral,, uint256 debt, uint256 supplied,,,,, bool isActive,,,,) =
            leverageContract.positions(deployer);
        require(isActive, "Error: No active position found for this address. Cannot close.");

        console.log("\nActive Position Found:");
        console.log("  - Initial Collateral:    %s LINK", _formatAmount(collateral, LINK_DECIMALS, 4));
        console.log("  - Total LINK Supplied:   %s LINK", _formatAmount(supplied, LINK_DECIMALS, 4));
        console.log("  - Aave Debt to Repay:    %s USDC", _formatAmount(debt, USDC_DECIMALS, 2));
        console.log(unicode"✅ Checks Passed: Ready to close position.");

        // --- 2. Execution ---
        console.log(unicode"\n⚙️ --- 2. Execution --- ⚙️");
        vm.startBroadcast();

        console.log("   - Calling closeLeveragePosition()...");
        leverageContract.closeLeveragePosition();

        vm.stopBroadcast();
        console.log(unicode"✅ Transaction successful!");

        // --- 3. Verification & Final State ---
        console.log(unicode"\n📊 --- 3. Verification & Final State --- 📊");

        (,,,,,,,, bool positionIsNowActive,,,,) = leverageContract.positions(deployer);
        require(!positionIsNowActive, "Verification FAILED: Position is still marked as active.");
        console.log(unicode"✅ Position struct successfully deleted on-chain.");

        uint256 finalLinkBalance = link.balanceOf(deployer);

        console.log("\n=== Balance Change Summary ===");
        console.log("  - LINK Balance Before Close: %s LINK", _formatAmount(initialLinkBalance, LINK_DECIMALS, 4));
        console.log("  - LINK Balance After Close:  %s LINK", _formatAmount(finalLinkBalance, LINK_DECIMALS, 4));
        console.log("---------------------------------------");

        if (finalLinkBalance > initialLinkBalance) {
            uint256 profit = finalLinkBalance - initialLinkBalance;
            console.log(unicode"  🎊 Profit:                    %s LINK", _formatAmount(profit, LINK_DECIMALS, 6));
        } else {
            uint256 loss = initialLinkBalance - finalLinkBalance;
            console.log(unicode"  📉 Loss:                     %s LINK", _formatAmount(loss, LINK_DECIMALS, 6));
        }

        console.log("\n=====================================");
        console.log(unicode"        ✅ Test Complete ✅         ");
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
