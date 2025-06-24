// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/interfaces/ISharedInterfaces.sol";

interface IAaveFaucet {
    function mint(address token, address to, uint256 amount) external returns (uint256);
}

contract MintUSDCLiquidity is Script {
    IAaveFaucet constant AAVE_FAUCET = IAaveFaucet(0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D);
    uint256 constant USDC_DECIMALS = 6;

    function run() external {
        // Load deployment addresses from JSON
        string memory deploymentFile = vm.readFile("deployments/sepolia.json");
        
        address creditShaftCore = vm.parseJsonAddress(deploymentFile, ".contracts.CreditShaftCore");
        address usdcToken = vm.parseJsonAddress(deploymentFile, ".dependencies.USDC");
        
        require(creditShaftCore != address(0), "CreditShaftCore address not found in deployment file");
        require(usdcToken != address(0), "USDC address not found in deployment file");

        console.log("=========================================");
        console.log("      MINT USDC LIQUIDITY SCRIPT");
        console.log("=========================================");
        console.log("CreditShaft Core Address: %s", creditShaftCore);
        console.log("USDC Token Address: %s", usdcToken);
        console.log("-----------------------------------------");

        // Set very high gas fees for extremely fast transactions
        vm.txGasPrice(50 gwei);        // Very high gas price for fast inclusion
        vm.fee(10 gwei);               // Very high priority fee for EIP-1559
        
        vm.startBroadcast();

        IERC20 usdc = IERC20(usdcToken);
        CreditShaftCore core = CreditShaftCore(creditShaftCore);

        // Check initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(msg.sender);
        uint256 initialCreditShaftLiquidity = core.getTotalUSDCLiquidity();

        console.log("Initial USDC Balance: %s", initialUsdcBalance / (10 ** USDC_DECIMALS));
        console.log("Initial CreditShaft Liquidity: %s", initialCreditShaftLiquidity / (10 ** USDC_DECIMALS));
        console.log("-----------------------------------------");

        // Mint 100K USDC
        console.log("=== MINTING 100K USDC ===");
        uint256 totalAmountToMint = 100_000;
        uint256 faucetMintLimit = 10_000;

        for (uint256 i = 0; i < totalAmountToMint / faucetMintLimit; i++) {
            AAVE_FAUCET.mint(usdcToken, msg.sender, faucetMintLimit * (10 ** USDC_DECIMALS));
            console.log("Minted batch %s: %s USDC", i + 1, faucetMintLimit);
        }

        uint256 finalUsdcBalance = usdc.balanceOf(msg.sender);
        uint256 mintedAmount = finalUsdcBalance - initialUsdcBalance;

        console.log("Total USDC Minted: %s", mintedAmount / (10 ** USDC_DECIMALS));
        console.log("Final USDC Balance: %s", finalUsdcBalance / (10 ** USDC_DECIMALS));
        console.log("-----------------------------------------");

        // Add all minted USDC to CreditShaft
        console.log("=== ADDING USDC TO CREDITSHAFT ===");

        require(address(core.usdc()) == usdcToken, "CreditShaft uses different USDC token");
        require(mintedAmount > 0, "No USDC was minted");

        console.log("Adding %s USDC to CreditShaft Core...", mintedAmount / (10 ** USDC_DECIMALS));
        usdc.approve(creditShaftCore, mintedAmount);
        core.addUSDCLiquidity(mintedAmount);

        // Verify final state
        uint256 finalCreditShaftLiquidity = core.getTotalUSDCLiquidity();
        uint256 finalAvailableLiquidity = core.getAvailableUSDCLiquidity();
        uint256 finalUserBalance = usdc.balanceOf(msg.sender);

        console.log("Final CreditShaft Total Liquidity: %s", finalCreditShaftLiquidity / (10 ** USDC_DECIMALS));
        console.log("Final CreditShaft Available Liquidity: %s", finalAvailableLiquidity / (10 ** USDC_DECIMALS));
        console.log("Final User USDC Balance: %s", finalUserBalance / (10 ** USDC_DECIMALS));
        console.log(
            "Liquidity Added: %s", (finalCreditShaftLiquidity - initialCreditShaftLiquidity) / (10 ** USDC_DECIMALS)
        );

        console.log("=========================================");
        console.log("[OK] Successfully minted and added 100K USDC to CreditShaft");
        console.log("=========================================");

        vm.stopBroadcast();
    }
}
