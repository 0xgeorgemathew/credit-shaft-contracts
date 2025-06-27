// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/CreditShaftCore.sol";
import "../src/CreditShaftLeverage.sol";
import "../src/SimplifiedLPToken.sol";
import {IERC20} from "../src/interfaces/ISharedInterfaces.sol";

/**
 * @title CreditShaftStats
 * @notice A script to display comprehensive protocol statistics in human-readable format
 */
contract CreditShaftStats is Script {
    // --- Constants ---
    uint256 constant LINK_DECIMALS = 18;
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant PRICE_FEED_DECIMALS = 8;
    uint256 constant PERCENTAGE_DECIMALS = 2;

    // --- State Variables ---
    address creditShaftCoreAddress;
    address creditShaftLeverageAddress;
    address simplifiedLPTokenAddress;
    address linkTokenAddress;
    address usdcTokenAddress;
    
    CreditShaftCore coreContract;
    CreditShaftLeverage leverageContract;
    SimplifiedLPToken lpToken;
    IERC20 link;
    IERC20 usdc;

    function run() external {
        _loadDeploymentAddresses();
        
        // Initialize contracts
        coreContract = CreditShaftCore(creditShaftCoreAddress);
        leverageContract = CreditShaftLeverage(creditShaftLeverageAddress);
        lpToken = SimplifiedLPToken(simplifiedLPTokenAddress);
        link = IERC20(linkTokenAddress);
        usdc = IERC20(usdcTokenAddress);

        console.log("\n===============================================");
        console.log(unicode"   📊 CreditShaft Protocol Stats 📊   ");
        console.log("===============================================");

        _displayProtocolOverview();
        _displayActivePositionsSummary();
        _displayIndividualPositions();
        _displayUpkeepStats();

        console.log("\n===============================================");
        console.log(unicode"        📈 Stats Complete 📈         ");
        console.log("===============================================");
    }

    function _displayProtocolOverview() internal view {
        console.log(unicode"\n💰 --- Flash Loan Pool Stats --- 💰");
        console.log(unicode"  ╭─────────────────────────────────────────╮");
        
        uint256 totalLiquidity = coreContract.totalUSDCLiquidity();
        uint256 totalFees = coreContract.totalFlashLoanFees();
        uint256 totalSupply = lpToken.totalSupply();
        uint256 currentBalance = usdc.balanceOf(creditShaftCoreAddress);
        
        console.log("  - Total USDC Liquidity:     $%s", _formatAmount(totalLiquidity, USDC_DECIMALS, 2));
        console.log("  - Accumulated LP Fees:      $%s", _formatAmount(totalFees, USDC_DECIMALS, 2));
        console.log("  - LP Token Supply:           %s cscLP", _formatAmount(totalSupply, USDC_DECIMALS, 2));
        console.log("  - Current USDC Balance:      $%s", _formatAmount(currentBalance, USDC_DECIMALS, 2));
        
        if (totalSupply > 0) {
            uint256 totalPool = totalLiquidity + totalFees;
            uint256 exchangeRate = (totalPool * 1e6) / totalSupply; // Rate in USDC per LP token
            console.log("  - LP Token Exchange Rate:    $%s per cscLP", _formatAmount(exchangeRate, USDC_DECIMALS, 4));
        }

        console.log(unicode"\n⚙️ --- Protocol Parameters --- ⚙️");
        console.log("  - Max Leverage:              %dx", leverageContract.MAX_LEVERAGE() / 100);
        console.log("  - Min Leverage:              %dx", leverageContract.MIN_LEVERAGE() / 100);
        console.log("  - LP Profit Share:           %d%%", leverageContract.LP_PROFIT_SHARE() / 100);
        console.log("  - PreAuth Multiplier:        %d%%", leverageContract.PREAUTH_MULTIPLIER());
        console.log("  - Safe LTV:                  %d%%", leverageContract.SAFE_LTV() / 100);
        console.log(unicode"  ╰─────────────────────────────────────────╯");
    }

    function _displayActivePositionsSummary() internal view {
        console.log(unicode"\n⚡ --- Active Positions Summary --- ⚡");
        console.log(unicode"  ╭─────────────────────────────────────────╮");
        
        uint256 activeCount = 0;
        uint256 totalCollateralLINK = 0;
        uint256 totalSuppliedLINK = 0;
        uint256 totalBorrowedUSDC = 0;
        uint256 totalLTV = 0;
        uint256 validLTVCount = 0;

        // Count active positions and aggregate stats
        for (uint256 i = 0; i < 100; i++) { // Reasonable limit to prevent gas issues
            try leverageContract.activeUsers(i) returns (address user) {
                (
                    uint256 collateralLINK,
                    ,
                    uint256 borrowedUSDC,
                    uint256 suppliedLINK,
                    ,
                    ,
                    ,
                    ,
                    bool isActive,
                    ,
                    ,
                    ,
                    
                ) = leverageContract.positions(user);
                
                if (isActive) {
                    activeCount++;
                    totalCollateralLINK += collateralLINK;
                    totalSuppliedLINK += suppliedLINK;
                    totalBorrowedUSDC += borrowedUSDC;
                    
                    // Calculate LTV for this position
                    uint256 positionLTV = _calculateLTV(user);
                    if (positionLTV > 0) {
                        totalLTV += positionLTV;
                        validLTVCount++;
                    }
                }
            } catch {
                break; // End of array reached
            }
        }

        console.log("  - Total Active Positions:    %d", activeCount);
        console.log("  - Total Collateral:          %s LINK", _formatAmount(totalCollateralLINK, LINK_DECIMALS, 4));
        console.log("  - Total Exposure:            %s LINK", _formatAmount(totalSuppliedLINK, LINK_DECIMALS, 4));
        console.log("  - Total Borrowed:            $%s", _formatAmount(totalBorrowedUSDC, USDC_DECIMALS, 2));

        if (totalCollateralLINK > 0) {
            uint256 linkPrice = leverageContract.getLINKPrice();
            uint256 totalCollateralUSD = (totalCollateralLINK * linkPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));
            uint256 totalExposureUSD = (totalSuppliedLINK * linkPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));
            
            console.log("  - Total Collateral Value:    $%s", _formatAmount(totalCollateralUSD, USDC_DECIMALS, 2));
            console.log("  - Total Exposure Value:      $%s", _formatAmount(totalExposureUSD, USDC_DECIMALS, 2));
        }
        
        // Display average LTV
        if (validLTVCount > 0) {
            uint256 avgLTV = totalLTV / validLTVCount;
            string memory avgLTVIcon = _getLTVStatusIcon(avgLTV);
            string memory avgLTVStatus = _getLTVStatusText(avgLTV);
            console.log("  - Average LTV:               %s %s%% (%s)", 
                avgLTVIcon, 
                _formatAmount(avgLTV, 2, 2), 
                avgLTVStatus);
        }
        console.log(unicode"  ╰─────────────────────────────────────────╯");
    }

    function _displayIndividualPositions() internal view {
        console.log(unicode"\n👥 --- Individual Positions --- 👥");
        
        uint256 linkPrice = leverageContract.getLINKPrice();
        uint256 positionCount = 0;

        for (uint256 i = 0; i < 20; i++) { // Display up to 20 positions
            try leverageContract.activeUsers(i) returns (address user) {
                (
                    uint256 collateralLINK,
                    uint256 leverageRatio,
                    uint256 borrowedUSDC,
                    uint256 suppliedLINK,
                    uint256 entryPrice,
                    uint256 preAuthAmount,
                    uint256 openTimestamp,
                    uint256 preAuthExpiryTime,
                    bool isActive,
                    bool preAuthCharged,
                    ,
                    ,
                    
                ) = leverageContract.positions(user);
                
                if (isActive) {
                    positionCount++;
                    console.log("\n=== Position #%d ===", positionCount);
                    console.log("  User Address:        %s", _formatAddress(user));
                    console.log("  Collateral:          %s LINK", _formatAmount(collateralLINK, LINK_DECIMALS, 4));
                    console.log("  Leverage:            %dx", leverageRatio / 100);
                    console.log("  Entry Price:         $%s", _formatAmount(entryPrice, PRICE_FEED_DECIMALS, 2));
                    console.log("  Current Price:       $%s", _formatAmount(linkPrice, PRICE_FEED_DECIMALS, 2));
                    
                    // Calculate P&L
                    if (entryPrice > 0) {
                        int256 priceChange = int256(linkPrice) - int256(entryPrice);
                        int256 pnlPercentage = (priceChange * 10000) / int256(entryPrice); // Basis points
                        
                        if (priceChange >= 0) {
                            console.log("  Price Change:        +%s%% (+$%s)", 
                                _formatSignedAmount(pnlPercentage, 2, 2), 
                                _formatAmount(uint256(priceChange), PRICE_FEED_DECIMALS, 2));
                        } else {
                            console.log("  Price Change:        -%s%% (-$%s)", 
                                _formatSignedAmount(-pnlPercentage, 2, 2), 
                                _formatAmount(uint256(-priceChange), PRICE_FEED_DECIMALS, 2));
                        }

                        // Calculate position P&L
                        uint256 currentValue = (suppliedLINK * linkPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));
                        uint256 entryValue = (suppliedLINK * entryPrice) / (10 ** (LINK_DECIMALS + PRICE_FEED_DECIMALS - USDC_DECIMALS));
                        
                        if (currentValue >= entryValue) {
                            uint256 profit = currentValue - entryValue;
                            console.log("  Position P&L:        +$%s", _formatAmount(profit, USDC_DECIMALS, 2));
                        } else {
                            uint256 loss = entryValue - currentValue;
                            console.log("  Position P&L:        -$%s", _formatAmount(loss, USDC_DECIMALS, 2));
                        }
                    }
                    
                    console.log("  Total Exposure:      %s LINK", _formatAmount(suppliedLINK, LINK_DECIMALS, 4));
                    console.log("  Borrowed Amount:     $%s", _formatAmount(borrowedUSDC, USDC_DECIMALS, 2));
                    
                    // Calculate and display LTV
                    uint256 currentLTV = _calculateLTV(user);
                    string memory ltvIcon = _getLTVStatusIcon(currentLTV);
                    string memory ltvStatus = _getLTVStatusText(currentLTV);
                    console.log("  Current LTV:         %s %s%% (%s)", 
                        ltvIcon, 
                        _formatAmount(currentLTV, 2, 2), 
                        ltvStatus);
                    
                    console.log("  PreAuth Amount:      $%s", _formatAmount(preAuthAmount, USDC_DECIMALS, 2));
                    console.log("  Open Timestamp:      %d", openTimestamp);
                    console.log("  PreAuth Expiry:      %d", preAuthExpiryTime);
                    console.log("  PreAuth Charged:     %s", preAuthCharged ? "Yes" : "No");
                    
                    // Calculate PreAuth time remaining
                    if (block.timestamp < preAuthExpiryTime && !preAuthCharged) {
                        uint256 timeRemaining = preAuthExpiryTime - block.timestamp;
                        console.log("  PreAuth Time Left:   %s", _formatTimeRemaining(timeRemaining));
                    } else if (preAuthCharged) {
                        console.log("  PreAuth Time Left:   N/A (Already charged)");
                    } else {
                        console.log("  PreAuth Time Left:   0 minutes (Ready to charge)");
                    }
                    
                    // Position Status (always active if isActive=true, regardless of PreAuth)
                    console.log(unicode"  ✅ Position Status:    Active (Can be closed anytime)");
                    
                    // PreAuth Status (separate from position status)
                    if (preAuthCharged) {
                        console.log(unicode"  💳 PreAuth Status:     Charged");
                    } else if (block.timestamp >= preAuthExpiryTime) {
                        console.log(unicode"  ⚠️ PreAuth Status:     Expired - Ready for charging");
                    } else {
                        console.log(unicode"  ✅ PreAuth Status:     Active");
                    }
                }
            } catch {
                break; // End of array reached
            }
        }

        if (positionCount == 0) {
            console.log("  No active positions found.");
        }
    }

    function _displayUpkeepStats() internal view {
        console.log(unicode"\n🤖 --- Automation Stats --- 🤖");
        console.log(unicode"  ╭─────────────────────────────────────────╮");
        
        uint256 automationCounter = leverageContract.automationCounter();
        
        console.log("  - Automation Executions:     %d", automationCounter);
        console.log("  - Current Time:              %d", block.timestamp);

        // Check if upkeep is needed
        try leverageContract.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("  - Upkeep Needed:             %s", upkeepNeeded ? "Yes" : "No");
            if (upkeepNeeded && performData.length > 0) {
                console.log("  - Perform Data Length:       %d bytes", performData.length);
            }
        } catch {
            console.log("  - Upkeep Check:              Failed to check");
        }
        console.log(unicode"  ╰─────────────────────────────────────────╯");
    }

    function _formatAmount(uint256 amount, uint256 decimals, uint256 displayDecimals)
        internal
        pure
        returns (string memory)
    {
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = amount / divisor;

        if (displayDecimals == 0) {
            return _addCommas(vm.toString(integerPart));
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

        return string.concat(_addCommas(vm.toString(integerPart)), ".", fractionalString);
    }
    
    function _addCommas(string memory numStr) internal pure returns (string memory) {
        bytes memory numBytes = bytes(numStr);
        uint256 len = numBytes.length;
        
        if (len <= 3) return numStr;
        
        uint256 commaCount = (len - 1) / 3;
        bytes memory result = new bytes(len + commaCount);
        
        uint256 resultIndex = result.length;
        uint256 digitCount = 0;
        
        for (uint256 i = len; i > 0; i--) {
            if (digitCount > 0 && digitCount % 3 == 0) {
                resultIndex--;
                result[resultIndex] = ',';
            }
            resultIndex--;
            result[resultIndex] = numBytes[i - 1];
            digitCount++;
        }
        
        return string(result);
    }

    function _formatSignedAmount(int256 amount, uint256 decimals, uint256 displayDecimals)
        internal
        pure
        returns (string memory)
    {
        if (amount >= 0) {
            return _formatAmount(uint256(amount), decimals, displayDecimals);
        } else {
            return _formatAmount(uint256(-amount), decimals, displayDecimals);
        }
    }

    function _calculateLTV(address user) internal view returns (uint256) {
        (, , uint256 borrowedUSDC, uint256 suppliedLINK,,,,,bool isActive,,,,) = 
            leverageContract.positions(user);
        
        if (!isActive || suppliedLINK == 0) {
            return 0;
        }
        
        uint256 linkPrice = leverageContract.getLINKPrice();
        uint256 collateralValueUSD = (suppliedLINK * linkPrice) / 1e20; // Convert to USDC value
        
        if (collateralValueUSD == 0) return 10000; // 100% LTV if no collateral
        
        return (borrowedUSDC * 10000) / collateralValueUSD;
    }

    function _getLTVStatusIcon(uint256 ltv) internal pure returns (string memory) {
        if (ltv < 6000) return unicode"🟢"; // Safe (< 60%)
        if (ltv < 6500) return unicode"🟡"; // Warning (60-65%)
        return unicode"🔴"; // Unsafe (> 65%)
    }

    function _getLTVStatusText(uint256 ltv) internal pure returns (string memory) {
        if (ltv < 6000) return "Safe";
        if (ltv < 6500) return "Warning";
        return "Unsafe";
    }

    function _formatAddress(address addr) internal pure returns (string memory) {
        string memory addrStr = vm.toString(addr);
        bytes memory addrBytes = bytes(addrStr);
        if (addrBytes.length < 10) return addrStr;
        
        string memory prefix = "";
        string memory suffix = "";
        
        // Extract first 6 characters (0x + 4 hex digits)
        for (uint i = 0; i < 6; i++) {
            prefix = string.concat(prefix, string(abi.encodePacked(addrBytes[i])));
        }
        
        // Extract last 4 characters
        for (uint i = addrBytes.length - 4; i < addrBytes.length; i++) {
            suffix = string.concat(suffix, string(abi.encodePacked(addrBytes[i])));
        }
        
        return string.concat(prefix, "...", suffix);
    }

    function _formatTimeRemaining(uint256 timeRemaining) internal pure returns (string memory) {
        if (timeRemaining == 0) return "0 minutes";
        
        uint256 hoursPart = timeRemaining / 3600;
        uint256 minutesPart = (timeRemaining % 3600) / 60;
        
        if (hoursPart > 0) {
            if (minutesPart > 0) {
                return string.concat(vm.toString(hoursPart), "h ", vm.toString(minutesPart), "m");
            } else {
                return string.concat(vm.toString(hoursPart), " hours");
            }
        } else {
            return string.concat(vm.toString(minutesPart), " minutes");
        }
    }

    function _loadDeploymentAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/sepolia.json");
        string memory json = vm.readFile(path);
        
        creditShaftCoreAddress = vm.parseJsonAddress(json, ".contracts.CreditShaftCore");
        creditShaftLeverageAddress = vm.parseJsonAddress(json, ".contracts.CreditShaftLeverage");
        simplifiedLPTokenAddress = vm.parseJsonAddress(json, ".contracts.SimplifiedLPToken");
        linkTokenAddress = vm.parseJsonAddress(json, ".dependencies.LINK");
        usdcTokenAddress = vm.parseJsonAddress(json, ".dependencies.USDC");
        
        require(creditShaftCoreAddress != address(0), "Failed to load CreditShaftCore address");
        require(creditShaftLeverageAddress != address(0), "Failed to load CreditShaftLeverage address");
        require(simplifiedLPTokenAddress != address(0), "Failed to load SimplifiedLPToken address");
        require(linkTokenAddress != address(0), "Failed to load LINK token address");
        require(usdcTokenAddress != address(0), "Failed to load USDC token address");
    }
}