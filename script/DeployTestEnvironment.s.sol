// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaft.sol";

/**
 * @title DeployTestEnvironment
 * @dev Script to deploy CreditShaft with test configuration for local testing
 */
contract DeployTestEnvironment is Script {
    // Sepolia configuration
    address constant SEPOLIA_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant SEPOLIA_DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint64 constant TEST_SUBSCRIPTION_ID = 4986; // Your test subscription

    function run() external {
        // Use msg.sender which is set by forge when using --account and --sender flags
        address deployerAddress = msg.sender;

        vm.startBroadcast();

        // Deploy CreditShaft contract with test settings
        CreditShaft creditShaft = new CreditShaft(SEPOLIA_ROUTER, TEST_SUBSCRIPTION_ID, SEPOLIA_DON_ID);

        // Set up test secrets version (if provided in env)
        uint64 secretsVersion = uint64(vm.envOr("DON_HOSTED_SECRETS_VERSION", uint256(1750048992)));
        creditShaft.updateDONHostedSecretsVersion(secretsVersion);

        vm.stopBroadcast();

        console.log("=== CreditShaft Sepolia Environment Deployed ===");
        console.log("CreditShaft contract:", address(creditShaft));
        console.log("LP Token contract:", address(creditShaft.lpToken()));
        console.log("Functions Router:", SEPOLIA_ROUTER);
        console.log("Subscription ID:", TEST_SUBSCRIPTION_ID);
        console.log("DON ID:", vm.toString(SEPOLIA_DON_ID));
        console.log("Secrets Version:", secretsVersion);
        console.log("Deployer:", deployerAddress);

        // Output for easy copying to JavaScript files
        console.log("\n=== For JavaScript Integration ===");
        console.log('const CREDIT_SHAFT_ADDRESS = "%s";', address(creditShaft));
        console.log('const LP_TOKEN_ADDRESS = "%s";', address(creditShaft.lpToken()));
    }
}
