// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/AaveStrategy.sol";
import "../src/CreditShaftLeverage.sol";

/**
 * @title DeployCreditShaftLeverage
 * @dev Script to deploy CreditShaftLeverage with all dependencies and proper setup
 *
 * What this script DEPLOYS:
 * - CreditShaftCore (USDC flash loan provider)
 * - AaveStrategy (Aave V3 integration contract)
 * - CreditShaftLeverage (main leverage contract)
 * - SimplifiedLPToken (automatically deployed by CreditShaftLeverage constructor)
 *
 * What this script DOES NOT deploy:
 * - External dependencies (USDC, LINK, Aave Pool, Uniswap Router, Chainlink components)
 * - Does not add initial liquidity (requires separate funding)
 * - Does not configure Chainlink subscription (requires manual setup)
 */
contract DeployCreditShaftLeverage is Script {
    // Sepolia configuration
    address constant SEPOLIA_AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant SEPOLIA_UNISWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant SEPOLIA_LINK_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address constant SEPOLIA_USDC = 0xa0B86a33e6441C8FaFA04F8Cb0b99bb4C6659d31;
    address constant SEPOLIA_LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant SEPOLIA_DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint64 constant TEST_SUBSCRIPTION_ID = 4986;

    function run() external {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast();

        // Get secrets version from environment or use default
        uint64 secretsVersion = uint64(vm.envOr("DON_HOSTED_SECRETS_VERSION", uint256(1750465781)));

        // 1. Deploy CreditShaftCore (USDC flash loan provider)
        CreditShaftCore creditShaftCore = new CreditShaftCore(SEPOLIA_USDC);

        // 2. Deploy CreditShaftLeverage contract first (with temp address for AaveStrategy)
        CreditShaftLeverage creditShaftLeverage = new CreditShaftLeverage(
            address(creditShaftCore),
            address(0), // Temporary - will be updated after AaveStrategy deployment
            SEPOLIA_UNISWAP_ROUTER,
            SEPOLIA_LINK_PRICE_FEED,
            SEPOLIA_USDC,
            SEPOLIA_LINK,
            SEPOLIA_FUNCTIONS_ROUTER,
            SEPOLIA_DON_ID,
            secretsVersion,
            TEST_SUBSCRIPTION_ID
        );

        // 3. Deploy AaveStrategy with both Core and Leverage addresses
        AaveStrategy aaveStrategy =
            new AaveStrategy(SEPOLIA_AAVE_POOL, address(creditShaftCore), address(creditShaftLeverage));

        // 4. Update CreditShaftLeverage with actual AaveStrategy address
        creditShaftLeverage.setAaveStrategy(address(aaveStrategy));

        // 4. Post-deployment setup complete - no additional permissions needed
        // CreditShaftCore flash loans are publicly accessible

        vm.stopBroadcast();

        console.log("=== CreditShaft System Sepolia Deployment ===");
        console.log("CreditShaftCore contract:", address(creditShaftCore));
        console.log("AaveStrategy contract:", address(aaveStrategy));
        console.log("CreditShaftLeverage contract:", address(creditShaftLeverage));
        console.log("SimplifiedLPToken contract:", address(creditShaftLeverage.lpToken()));
        console.log("AAVE Pool:", SEPOLIA_AAVE_POOL);
        console.log("Uniswap Router:", SEPOLIA_UNISWAP_ROUTER);
        console.log("LINK Price Feed:", SEPOLIA_LINK_PRICE_FEED);
        console.log("USDC Token:", SEPOLIA_USDC);
        console.log("LINK Token:", SEPOLIA_LINK);
        console.log("Functions Router:", SEPOLIA_FUNCTIONS_ROUTER);
        console.log("DON ID:", vm.toString(SEPOLIA_DON_ID));
        console.log("Secrets Version:", secretsVersion);
        console.log("Deployer:", deployerAddress);

        // Output for easy copying to JavaScript files
        console.log("\n=== For JavaScript Integration ===");
        console.log('const CREDIT_SHAFT_CORE_ADDRESS = "%s";', address(creditShaftCore));
        console.log('const AAVE_STRATEGY_ADDRESS = "%s";', address(aaveStrategy));
        console.log('const CREDIT_SHAFT_LEVERAGE_ADDRESS = "%s";', address(creditShaftLeverage));
        console.log('const LP_TOKEN_ADDRESS = "%s";', address(creditShaftLeverage.lpToken()));

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Add USDC liquidity: Call addUSDCLiquidity() on CreditShaftCore");
        console.log("2. Add contract to Chainlink subscription #%s", TEST_SUBSCRIPTION_ID);
        console.log("3. Fund subscription with LINK tokens");
        console.log("4. Ready for demo!");
    }
}
