// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/AaveStrategy.sol";
import "../src/CreditShaftLeverage.sol";
import "../src/SimplifiedLPToken.sol";

import {IAaveFaucet} from "../src/interfaces/ISharedInterfaces.sol";

/**
 * @title DeployCreditShaftLeverage
 * @dev Script to deploy CreditShaftLeverage with all dependencies and proper setup
 *
 * What this script DEPLOYS:
 * - CreditShaftCore (USDC flash loan provider with LP token)
 * - AaveStrategy (Aave V3 integration contract)
 * - CreditShaftLeverage (main leverage contract)
 *
 * What this script DOES NOT deploy:
 * - External dependencies (USDC, LINK, Aave Pool, Uniswap Router, Chainlink components)
 * - Does not configure Chainlink subscription (requires manual setup)
 *
 * ARCHITECTURE NOTE:
 * - CreditShaftCore provides flash loans and has LP token for liquidity providers
 * - CreditShaftLeverage executes leveraged trades using flash loans from Core
 * - 20% of leverage trading profits flow back to CreditShaftCore LPs as rewards
 */
contract DeployCreditShaftLeverage is Script {
    // Sepolia configuration
    address constant SEPOLIA_AAVE_POOL = 0xccEa5C65f6d4F465B71501418b88FBe4e7071283;
    address constant SEPOLIA_UNISWAP_ROUTER = 0x2D99ABD9008Dc933ff5c0CD271B88309593aB921;
    address constant SEPOLIA_LINK_PRICE_FEED = 0x97cd7dc7DAA77E577C544Da7131e466952a72e9D; // Aave's MockAggregator for LINK ($30.00)
    address constant SEPOLIA_USDC = 0xCaC7Ffa82c0f43EBB0FC11FCd32123EcA46626cf; // Correct faucet USDC
    address constant SEPOLIA_LINK = 0x3A38c4d0444b5fFcc5323b2e86A21aBaaf5FbF26; // Correct faucet LINK
    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0;
    bytes32 constant SEPOLIA_DON_ID = 0x66756e2d6176616c616e6368652d66756a692d31000000000000000000000000;
    uint64 constant TEST_SUBSCRIPTION_ID = 15686;
    IAaveFaucet constant AAVE_FAUCET = IAaveFaucet(0xBCcD21ae43139bEF545e72e20E78f039A3Ac1b96);
    uint256 constant USDC_DECIMALS = 6;

    function run() external {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        // Set very high gas fees for extremely fast transactions
        vm.txGasPrice(50 gwei); // Very high gas price for fast inclusion
        vm.fee(10 gwei); // Very high priority fee for EIP-1559

        vm.startBroadcast();

        // Get secrets version from environment or use default
        uint64 secretsVersion = uint64(1751163391); // Default

        // 1. Deploy SimplifiedLPToken first
        SimplifiedLPToken lpToken = new SimplifiedLPToken("CreditShaft Core LP", "cscLP");

        // 2. Deploy CreditShaftCore (USDC flash loan provider) with LP token address
        CreditShaftCore creditShaftCore = new CreditShaftCore(SEPOLIA_USDC, address(lpToken));

        // 3. Deploy CreditShaftLeverage contract first (with temp address for AaveStrategy)
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

        // 4. Deploy AaveStrategy with both Core and Leverage addresses
        AaveStrategy aaveStrategy =
            new AaveStrategy(SEPOLIA_AAVE_POOL, address(creditShaftCore), address(creditShaftLeverage));

        // 5. Update CreditShaftLeverage with actual AaveStrategy address
        creditShaftLeverage.setAaveStrategy(address(aaveStrategy));

        // 6. Transfer LP token ownership to CreditShaftCore so it can mint/burn tokens
        lpToken.transferOwnership(address(creditShaftCore));

        // 7. Post-deployment setup complete - no additional permissions needed
        // CreditShaftCore flash loans are publicly accessible
        vm.stopBroadcast();

        // Write deployment addresses to JSON file
        string memory deploymentJson = string.concat(
            "{\n",
            '  "network": "sepolia",\n',
            '  "timestamp": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "deployer": "',
            vm.toString(deployerAddress),
            '",\n',
            '  "contracts": {\n',
            '    "SimplifiedLPToken": "',
            vm.toString(address(lpToken)),
            '",\n',
            '    "CreditShaftCore": "',
            vm.toString(address(creditShaftCore)),
            '",\n',
            '    "AaveStrategy": "',
            vm.toString(address(aaveStrategy)),
            '",\n',
            '    "CreditShaftLeverage": "',
            vm.toString(address(creditShaftLeverage)),
            '"\n',
            "  },\n",
            '  "dependencies": {\n',
            '    "AAVE_POOL": "',
            vm.toString(SEPOLIA_AAVE_POOL),
            '",\n',
            '    "UNISWAP_ROUTER": "',
            vm.toString(SEPOLIA_UNISWAP_ROUTER),
            '",\n',
            '    "LINK_PRICE_FEED": "',
            vm.toString(SEPOLIA_LINK_PRICE_FEED),
            '",\n',
            '    "USDC": "',
            vm.toString(SEPOLIA_USDC),
            '",\n',
            '    "LINK": "',
            vm.toString(SEPOLIA_LINK),
            '",\n',
            '    "FUNCTIONS_ROUTER": "',
            vm.toString(SEPOLIA_FUNCTIONS_ROUTER),
            '",\n',
            '    "DON_ID": "',
            vm.toString(SEPOLIA_DON_ID),
            '",\n',
            '    "SECRETS_VERSION": "',
            vm.toString(secretsVersion),
            '",\n',
            '    "SUBSCRIPTION_ID": "',
            vm.toString(TEST_SUBSCRIPTION_ID),
            '"\n',
            "  }\n",
            "}"
        );

        vm.writeFile("deployments/sepolia.json", deploymentJson);

        console.log("=== CreditShaft System Sepolia Deployment ===");
        console.log("SimplifiedLPToken contract:", address(lpToken));
        console.log("CreditShaftCore contract:", address(creditShaftCore));
        console.log("AaveStrategy contract:", address(aaveStrategy));
        console.log("CreditShaftLeverage contract:", address(creditShaftLeverage));
        console.log("AAVE Pool:", SEPOLIA_AAVE_POOL);
        console.log("Uniswap Router:", SEPOLIA_UNISWAP_ROUTER);
        console.log("LINK Price Feed:", SEPOLIA_LINK_PRICE_FEED);
        console.log("USDC Token:", SEPOLIA_USDC);
        console.log("LINK Token:", SEPOLIA_LINK);
        console.log("Functions Router:", SEPOLIA_FUNCTIONS_ROUTER);
        console.log("DON ID:", vm.toString(SEPOLIA_DON_ID));
        console.log("Secrets Version:", secretsVersion);
        console.log("Deployer:", deployerAddress);
        console.log("Deployment addresses saved to: deployments/sepolia.json");

        // Output for easy copying to JavaScript files
        console.log("\n=== For JavaScript Integration ===");
        console.log('const SIMPLIFIED_LP_TOKEN_ADDRESS = "%s";', address(lpToken));
        console.log('const CREDIT_SHAFT_CORE_ADDRESS = "%s";', address(creditShaftCore));
        console.log('const AAVE_STRATEGY_ADDRESS = "%s";', address(aaveStrategy));
        console.log('const CREDIT_SHAFT_LEVERAGE_ADDRESS = "%s";', address(creditShaftLeverage));

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Add USDC liquidity: Call addUSDCLiquidity() on CreditShaftCore (for flash loan LPs)");
        console.log("2. Add contract to Chainlink subscription #%s", TEST_SUBSCRIPTION_ID);
        console.log("3. Fund subscription with LINK tokens");
        console.log("4. Ready for demo!");
    }
}
