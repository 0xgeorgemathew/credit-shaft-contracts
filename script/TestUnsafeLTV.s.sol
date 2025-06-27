// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/CreditShaftLeverage.sol";
import "../src/AaveStrategy.sol";
import "../src/interfaces/ISharedInterfaces.sol";

contract TestUnsafeLTV is Script {
    CreditShaftLeverage public creditShaftLeverage;
    AaveStrategy public aaveStrategy;
    IERC20 public usdc;
    IERC20 public link;
    
    function setUp() public {
        // Load deployed contract addresses from sepolia.json
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployments/sepolia.json"));
        string memory json = vm.readFile(path);
        
        address leverageAddress = vm.parseJsonAddress(json, ".contracts.CreditShaftLeverage");
        address strategyAddress = vm.parseJsonAddress(json, ".contracts.AaveStrategy");
        
        creditShaftLeverage = CreditShaftLeverage(leverageAddress);
        aaveStrategy = AaveStrategy(strategyAddress);
        
        // Token addresses on Sepolia
        usdc = IERC20(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8);
        link = IERC20(0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5);
    }
    
    function run() external {
        address deployer = msg.sender;
        
        vm.startBroadcast();
        
        console.log("=== Testing Unsafe LTV Position ===");
        console.log("Deployer:", deployer);
        
        // Check if user has an active position
        (, uint256 leverageRatio, uint256 borrowedUSDC, uint256 suppliedLINK,,,,,bool isActive,,,,) = 
            creditShaftLeverage.positions(deployer);
        
        if (!isActive) {
            console.log("ERROR: No active position found. Please open a position first.");
            vm.stopBroadcast();
            return;
        }
        
        console.log("Current Position:");
        console.log("- Leverage Ratio:", leverageRatio);
        console.log("- Borrowed USDC:", borrowedUSDC);
        console.log("- Supplied LINK:", suppliedLINK);
        
        // Calculate current LTV
        uint256 currentLTV = _calculateLTV(deployer);
        console.log("- Current LTV:", currentLTV, "basis points");
        
        // Calculate how much more USDC to borrow to reach 67% LTV (above our 65% safety threshold)
        uint256 targetLTV = 6700; // 67% - above our 65% automation threshold but below Aave's 70% max LTV
        uint256 linkPrice = creditShaftLeverage.getLINKPrice();
        uint256 collateralValueUSD = (suppliedLINK * linkPrice) / 1e20; // Convert to USDC value
        uint256 targetDebt = (collateralValueUSD * targetLTV) / 10000;
        
        if (targetDebt <= borrowedUSDC) {
            console.log("Position is already at or above target LTV");
        } else {
            uint256 additionalBorrow = targetDebt - borrowedUSDC;
            console.log("Need to borrow additional USDC:", additionalBorrow);
            
            // Borrow more USDC to push LTV above 70%
            console.log("Borrowing additional USDC to make position unsafe...");
            creditShaftLeverage.borrowMoreUSDC(additionalBorrow);
            
            // Check new LTV
            uint256 newLTV = _calculateLTV(deployer);
            console.log("New LTV after borrowing:", newLTV, "basis points");
            
            if (newLTV > 6500) {
                console.log("SUCCESS: Position is now unsafe (LTV > 65%)!");
                console.log("Chainlink Automation should close this position.");
            } else {
                console.log("WARNING: Position LTV is still below 65% threshold.");
            }
        }
        
        // Test checkUpkeep to see if automation detects the unsafe position
        console.log("\n=== Testing Automation Detection ===");
        (bool upkeepNeeded, bytes memory performData) = creditShaftLeverage.checkUpkeep("");
        
        if (upkeepNeeded) {
            console.log("SUCCESS: checkUpkeep detected action needed!");
            
            // Decode performData to see what actions are needed
            (, uint256 chargeCount, address[] memory usersToClose, uint256 closeCount) = 
                abi.decode(performData, (address[], uint256, address[], uint256));
            
            console.log("Users to charge PreAuth:", chargeCount);
            console.log("Users to close positions:", closeCount);
            
            if (closeCount > 0) {
                console.log("Position closure detected for users:");
                for (uint256 i = 0; i < closeCount; i++) {
                    console.log("-", usersToClose[i]);
                }
            }
        } else {
            console.log("No upkeep needed - automation may not have detected unsafe position yet.");
        }
        
        vm.stopBroadcast();
    }
    
    function _calculateLTV(address user) internal view returns (uint256) {
        (, , uint256 borrowedUSDC, uint256 suppliedLINK,,,,,bool isActive,,,,) = 
            creditShaftLeverage.positions(user);
        
        if (!isActive || suppliedLINK == 0) {
            return 0;
        }
        
        uint256 linkPrice = creditShaftLeverage.getLINKPrice();
        uint256 collateralValueUSD = (suppliedLINK * linkPrice) / 1e20; // Convert to USDC value
        
        if (collateralValueUSD == 0) return 10000; // 100% LTV if no collateral
        
        return (borrowedUSDC * 10000) / collateralValueUSD;
    }
}