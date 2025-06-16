// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaft.sol";

contract DeployCreditShaft is Script {
    // Sepolia network configuration
    address constant SEPOLIA_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant SEPOLIA_DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint64 subscriptionId = uint64(vm.envUint("CHAINLINK_SUBSCRIPTION_ID"));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CreditShaft contract
        CreditShaft creditShaft = new CreditShaft(
            SEPOLIA_ROUTER,
            subscriptionId,
            SEPOLIA_DON_ID
        );
        
        console.log("CreditShaft deployed to:", address(creditShaft));
        console.log("LP Token deployed to:", address(creditShaft.lpToken()));
        console.log("Router address:", SEPOLIA_ROUTER);
        console.log("Subscription ID:", subscriptionId);
        console.log("DON ID:", vm.toString(SEPOLIA_DON_ID));
        
        vm.stopBroadcast();
    }
}