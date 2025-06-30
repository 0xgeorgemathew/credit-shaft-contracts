// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CCIPLiquidityManager} from "../src/CCIPLiquidityManager.sol";

// =================================================================
// SCRIPT 1: For Deployment (This part is unchanged and works)
// =================================================================
contract DeployManager is Script {
    function run() public {
        vm.startBroadcast();
        if (block.chainid == 11155111) {
            // Sepolia
            deploySepoliaManager();
        } else if (block.chainid == 43113) {
            // Fuji
            deployFujiManager();
        } else {
            revert("Unsupported chain ID.");
        }
        vm.stopBroadcast();
    }

    function deploySepoliaManager() internal {
        console.log("Deploying CCIPLiquidityManager to Sepolia...");
        new CCIPLiquidityManager(
            vm.envAddress("SEPOLIA_CCIP_ROUTER"),
            vm.envAddress("SEPOLIA_LINK_TOKEN"),
            vm.envAddress("SEPOLIA_USDC_TOKEN"),
            vm.envAddress("SEPOLIA_CREDIT_SHAFT_CORE")
        );
    }

    function deployFujiManager() internal {
        console.log("Deploying CCIPLiquidityManager to Fuji...");
        new CCIPLiquidityManager(
            vm.envAddress("FUJI_CCIP_ROUTER"),
            vm.envAddress("FUJI_LINK_TOKEN"),
            vm.envAddress("FUJI_USDC_TOKEN"),
            address(0)
        );
    }
}

// =================================================================
// SCRIPT 2: For Configuring ONLY the SEPOLIA Manager
// =================================================================
contract ConfigureSepoliaManager is Script {
    function run() public {
        // --- PASTE BOTH DEPLOYED ADDRESSES HERE ---
        address sepoliaManagerAddress = 0xa56010D091A945e54A0e457e447058483c751C18;
        address fujiManagerAddress = 0xa56010D091A945e54A0e457e447058483c751C18;

        // Sanity check
        require(sepoliaManagerAddress != address(0) && fujiManagerAddress != address(0));

        vm.startBroadcast();

        console.log("Configuring Sepolia Manager at", sepoliaManagerAddress);
        CCIPLiquidityManager manager = CCIPLiquidityManager(sepoliaManagerAddress);

        manager.setPartner(vm.envUint("FUJI_CHAIN_SELECTOR"), fujiManagerAddress);
        manager.setLiquidityParameters(vm.envUint("LIQUIDITY_THRESHOLD"), vm.envUint("REFILL_AMOUNT"));

        console.log(unicode"✅ Sepolia Manager configured.");

        vm.stopBroadcast();
    }
}

// =================================================================
// SCRIPT 3: For Configuring ONLY the FUJI Manager
// =================================================================
contract ConfigureFujiManager is Script {
    function run() public {
        // --- PASTE BOTH DEPLOYED ADDRESSES HERE ---
        address sepoliaManagerAddress = 0xa56010D091A945e54A0e457e447058483c751C18;
        address fujiManagerAddress = 0xa56010D091A945e54A0e457e447058483c751C18;

        // Sanity check
        require(sepoliaManagerAddress != address(0) && fujiManagerAddress != address(0));

        vm.startBroadcast();

        console.log("Configuring Fuji Manager at", fujiManagerAddress);
        CCIPLiquidityManager manager = CCIPLiquidityManager(fujiManagerAddress);

        manager.setPartner(vm.envUint("SEPOLIA_CHAIN_SELECTOR"), sepoliaManagerAddress);

        console.log(unicode"✅ Fuji Manager configured.");

        vm.stopBroadcast();
    }
}
