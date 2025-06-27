// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RepayAaveDebt
 * @notice A standalone utility script to repay USDC debt in Aave V3 on behalf of another user.
 * @dev This script performs the following actions:
 *      1. Reads the Payer (from private key), Debtor, and Amount from environment variables.
 *      2. Checks that the Payer has enough USDC to make the payment.
 *      3. Approves the Aave V3 Pool to spend the Payer's USDC.
 *      4. Calls `aavePool.repay()` to pay down the debt on behalf of the Debtor.
 *      5. Verifies the state change by checking the Debtor's updated debt amount.
 */
contract RepayAaveDebt is Script {
    // --- Sepolia Configuration ---
    // These addresses are for the official Aave V3 deployment on the Sepolia testnet.
    IPool constant AAVE_POOL = IPool(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951);
    IERC20 constant USDC = IERC20(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8);
    uint256 constant USDC_DECIMALS = 1e6;

    function run() external {
        // --- 1. Load Configuration from Environment ---
        address payerAddress = msg.sender; // The one executing and paying
        address debtorAddress = vm.envAddress("DEBTOR_ADDRESS"); // The user whose debt is being paid
        uint256 repayAmountHuman = vm.envUint("REPAY_AMOUNT"); // The amount in whole dollars (e.g., 5 for $5)

        require(debtorAddress != address(0), "DEBTOR_ADDRESS not set in .env file.");
        require(repayAmountHuman > 0, "REPAY_AMOUNT must be greater than 0.");

        // Scale the human-readable amount to the 6 decimals of USDC
        uint256 repayAmountScaled = repayAmountHuman * USDC_DECIMALS;

        console.log("\n=============================================");
        console.log(unicode"  💸 Aave V3 Debt Repayment Script 💸");
        console.log("=============================================");
        console.log(unicode"\n📋 --- Configuration --- 📋");
        console.log("Payer's Address:       ", payerAddress);
        console.log("Debtor's Address:      ", debtorAddress);
        console.log("Asset to Repay:        USDC");
        console.log("Amount to Repay:       %d USDC", repayAmountHuman);

        // --- 2. Pre-flight Checks ---
        console.log(unicode"\n🔎 --- Pre-flight Checks --- 🔎");
        uint256 payerBalance = USDC.balanceOf(payerAddress);
        console.log(
            "Payer's USDC Balance:    %d.%02d USDC",
            payerBalance / USDC_DECIMALS,
            (payerBalance * 100 / USDC_DECIMALS) % 100
        );
        require(payerBalance >= repayAmountScaled, "Error: Payer has insufficient USDC balance.");

        (, uint256 initialDebtBase,,,,) = AAVE_POOL.getUserAccountData(debtorAddress);
        require(initialDebtBase > 0, "Info: The specified debtor has no debt in Aave.");
        console.log(unicode"✅ Checks Passed: Payer has sufficient funds.");

        // --- 3. Execution ---
        console.log(unicode"\n⚙️ --- Execution --- ⚙️");
        vm.startBroadcast();

        console.log("   - Approving Aave Pool to spend %d USDC from Payer's wallet...", repayAmountHuman);
        USDC.approve(address(AAVE_POOL), repayAmountScaled);

        console.log("   - Calling Aave's repay() function on behalf of the Debtor...");
        // The `interestRateMode` parameter is not used in repay, but is required for the signature.
        // We can use `2` for variable, but `1` (stable) would also work.
        AAVE_POOL.repay(address(USDC), repayAmountScaled, 2, debtorAddress);

        vm.stopBroadcast();
        console.log(unicode"✅ Transaction successful!");

        // --- 4. Verification ---
        console.log(unicode"\n📊 --- Verification --- 📊");
        (, uint256 finalDebtBase,,,,) = AAVE_POOL.getUserAccountData(debtorAddress);

        console.log("Debtor's Initial Debt (in ETH base):", initialDebtBase);
        console.log("Debtor's Final Debt (in ETH base):  ", finalDebtBase);
        require(finalDebtBase < initialDebtBase, "Verification FAILED: Debtor's debt did not decrease.");

        console.log(unicode"✅ Verification Successful: The debtor's Aave debt has been reduced.");
        console.log("\n=============================================");
    }
}
