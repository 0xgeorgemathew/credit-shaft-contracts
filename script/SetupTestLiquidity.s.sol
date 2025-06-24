// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/interfaces/ISharedInterfaces.sol";

// Interfaces...
interface IAaveFaucet {
    function mint(address token, address to, uint256 amount) external returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function mint(address to) external returns (uint256 liquidity); // <--- Add this function
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

contract SetupTestLiquidity is Script {
    IAaveFaucet constant AAVE_FAUCET = IAaveFaucet(0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D);
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant LINK_DECIMALS = 18;

    function run() external {
        // Load deployment addresses from JSON
        string memory deploymentFile = vm.readFile("deployments/sepolia.json");
        
        address creditShaftCore = vm.parseJsonAddress(deploymentFile, ".contracts.CreditShaftCore");
        address usdcToken = vm.parseJsonAddress(deploymentFile, ".dependencies.USDC");
        address linkToken = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK");
        address uniswapRouter = vm.parseJsonAddress(deploymentFile, ".dependencies.UNISWAP_ROUTER");
        address linkPriceFeed = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK_PRICE_FEED");
        
        require(creditShaftCore != address(0), "CreditShaftCore address not found in deployment file");
        require(usdcToken != address(0), "USDC address not found in deployment file");
        require(linkToken != address(0), "LINK address not found in deployment file");
        
        IUniswapV2Router uniswapRouterContract = IUniswapV2Router(uniswapRouter);
        AggregatorV3Interface linkUsdPriceFeed = AggregatorV3Interface(linkPriceFeed);

        console.log("=========================================");
        console.log("      CREDIT SHAFT LIQUIDITY SETUP");
        console.log("=========================================");
        console.log("CreditShaft Core Address: %s", creditShaftCore);
        console.log("USDC Token Address: %s", usdcToken);
        console.log("LINK Token Address: %s", linkToken);
        console.log("Uniswap Router: %s", uniswapRouter);
        console.log("LINK/USD Price Feed: %s", linkPriceFeed);
        console.log("-----------------------------------------");

        // Set very high gas fees for extremely fast transactions
        vm.txGasPrice(50 gwei);        // Very high gas price for fast inclusion
        vm.fee(10 gwei);               // Very high priority fee for EIP-1559
        
        vm.startBroadcast();

        // --- Step 1: Mint tokens ---
        console.log("=== TOKEN MINTING ===\n");
        console.log("Minting tokens from Aave Faucet...");
        uint256 totalAmountToMint = 100_000;
        uint256 faucetMintLimit = 10_000;

        IERC20 usdc = IERC20(usdcToken);
        IERC20 link = IERC20(linkToken);

        uint256 initialUsdcBalance = usdc.balanceOf(msg.sender);
        uint256 initialLinkBalance = link.balanceOf(msg.sender);

        for (uint256 i = 0; i < totalAmountToMint / faucetMintLimit; i++) {
            AAVE_FAUCET.mint(usdcToken, msg.sender, faucetMintLimit * (10 ** USDC_DECIMALS));
            AAVE_FAUCET.mint(linkToken, msg.sender, faucetMintLimit * (10 ** LINK_DECIMALS));
        }

        uint256 finalUsdcBalance = usdc.balanceOf(msg.sender);
        uint256 finalLinkBalance = link.balanceOf(msg.sender);

        console.log(
            "Minted USDC: %s (Total Balance: %s)",
            (finalUsdcBalance - initialUsdcBalance) / (10 ** USDC_DECIMALS),
            finalUsdcBalance / (10 ** USDC_DECIMALS)
        );
        console.log(
            "Minted LINK: %s (Total Balance: %s)",
            (finalLinkBalance - initialLinkBalance) / (10 ** LINK_DECIMALS),
            finalLinkBalance / (10 ** LINK_DECIMALS)
        );
        console.log("-----------------------------------------\n");

        // --- Step 2: Get Oracle Price ---
        console.log("=== ORACLE PRICE INFORMATION ===\n");
        (, int256 linkPriceInt,,,) = linkUsdPriceFeed.latestRoundData();
        uint8 priceDecimals = linkUsdPriceFeed.decimals();
        uint256 linkPriceUSD = uint256(linkPriceInt);

        uint256 clPriceInteger = linkPriceUSD / (10 ** priceDecimals);
        uint256 clPriceFractional = (linkPriceUSD % (10 ** priceDecimals)) / 10 ** (priceDecimals - 2);
        console.log("Chainlink LINK/USD Price: $%s.%s", clPriceInteger, clPriceFractional);
        console.log("Price Feed Decimals: %s", priceDecimals);
        console.log("-----------------------------------------\n");

        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouterContract.factory());
        address pairAddress = factory.getPair(usdcToken, linkToken);
        require(pairAddress != address(0), "Pair does not exist");

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        uint256 currentUsdcReserve = 0;
        uint256 currentLinkReserve = 0;

        if (pair.token0() != address(0)) {
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            if (pair.token0() == usdcToken) {
                currentUsdcReserve = reserve0;
                currentLinkReserve = reserve1;
            } else {
                currentUsdcReserve = reserve1;
                currentLinkReserve = reserve0;
            }
        }

        console.log("=== POOL LIQUIDITY ANALYSIS ===\n");
        console.log("Uniswap Pair Address: %s", pairAddress);
        console.log("Current Pool Reserves:");
        console.log("  USDC: %s", currentUsdcReserve / (10 ** USDC_DECIMALS));
        console.log("  LINK: %s", currentLinkReserve / (10 ** LINK_DECIMALS));

        if (currentUsdcReserve > 0 && currentLinkReserve > 0) {
            uint256 currentPoolPrice = (currentUsdcReserve * (10 ** LINK_DECIMALS)) / currentLinkReserve;
            uint256 currentPriceInt = currentPoolPrice / (10 ** USDC_DECIMALS);
            uint256 currentPriceFrac = (currentPoolPrice % (10 ** USDC_DECIMALS)) / 10 ** (USDC_DECIMALS - 2);
            console.log("  Current Pool Price: 1 LINK = %s.%s USDC", currentPriceInt, currentPriceFrac);
        } else {
            console.log("  Pool is empty - no current price");
        }

        uint256 usdcToInject = 100_000 * (10 ** USDC_DECIMALS);
        uint256 targetTotalUsdc = currentUsdcReserve + usdcToInject;

        uint256 requiredTotalLink =
            (targetTotalUsdc * (10 ** LINK_DECIMALS) * (10 ** priceDecimals)) / (linkPriceUSD * (10 ** USDC_DECIMALS));

        console.log("\nTarget Pool Reserves (Oracle Price Aligned):");
        console.log("  USDC: %s", targetTotalUsdc / (10 ** USDC_DECIMALS));
        console.log("  LINK: %s", requiredTotalLink / (10 ** LINK_DECIMALS));

        uint256 usdcToAdd = targetTotalUsdc > currentUsdcReserve ? targetTotalUsdc - currentUsdcReserve : 0;
        uint256 linkToAdd = requiredTotalLink > currentLinkReserve ? requiredTotalLink - currentLinkReserve : 0;

        console.log("\nLiquidity to Add:");
        console.log("  USDC: %s", usdcToAdd / (10 ** USDC_DECIMALS));
        console.log("  LINK: %s", linkToAdd / (10 ** LINK_DECIMALS));
        console.log("-----------------------------------------\n");

        // --- Step 5: Add Liquidity DIRECTLY to the PAIR ---
        console.log("=== ADDING POOL LIQUIDITY ===\n");

        require(usdc.balanceOf(msg.sender) >= usdcToAdd, "Insufficient USDC balance");
        require(link.balanceOf(msg.sender) >= linkToAdd, "Insufficient LINK balance");

        if (usdcToAdd > 0) {
            usdc.transfer(pairAddress, usdcToAdd);
        }
        if (linkToAdd > 0) {
            link.transfer(pairAddress, linkToAdd);
        }

        if (usdcToAdd > 0 || linkToAdd > 0) {
            console.log("Adding liquidity directly to pair...");
            // This pulls in the tokens we just sent and mints LP tokens to us
            uint256 lpTokensMinted = pair.mint(msg.sender);
            console.log("LP Tokens Minted: %s", lpTokensMinted);
        } else {
            console.log("No liquidity needed - pool already at target");
        }

        // --- Step 6: Verify final pool price (Unchanged) ---
        (uint112 finalReserve0, uint112 finalReserve1,) = pair.getReserves();
        uint256 finalUsdcReserve;
        uint256 finalLinkReserve;
        if (pair.token0() == usdcToken) {
            finalUsdcReserve = finalReserve0;
            finalLinkReserve = finalReserve1;
        } else {
            finalUsdcReserve = finalReserve1;
            finalLinkReserve = finalReserve0;
        }

        uint256 poolPriceScaled = (finalUsdcReserve * (10 ** LINK_DECIMALS)) / finalLinkReserve;
        uint256 usdcPriceInteger = poolPriceScaled / (10 ** USDC_DECIMALS);
        uint256 usdcPriceFractional = (poolPriceScaled % (10 ** USDC_DECIMALS)) / 10 ** (USDC_DECIMALS - 2);

        console.log("\n=== FINAL POOL STATUS ===\n");
        console.log("Final Pool Reserves:");
        console.log("  USDC: %s", finalUsdcReserve / (10 ** USDC_DECIMALS));
        console.log("  LINK: %s", finalLinkReserve / (10 ** LINK_DECIMALS));

        uint256 totalPoolValueUSDC = finalUsdcReserve + ((finalLinkReserve * poolPriceScaled) / (10 ** LINK_DECIMALS));
        console.log("  Total Pool Value: %s USDC", totalPoolValueUSDC / (10 ** USDC_DECIMALS));

        console.log("\nPrice Comparison:");
        console.log("  Final Pool Price: 1 LINK = %s.%s USDC", usdcPriceInteger, usdcPriceFractional);
        console.log("  Oracle Price:     1 LINK = $%s.%s", clPriceInteger, clPriceFractional);
        console.log("-----------------------------------------\n");

        // --- Step 7: Add Remaining USDC to CreditShaft ---
        console.log("=== CREDIT SHAFT LIQUIDITY ===\n");
        CreditShaftCore core = CreditShaftCore(creditShaftCore);

        // Check CreditShaft liquidity before adding
        uint256 creditShaftUsdcBefore = core.getTotalUSDCLiquidity();
        uint256 creditShaftAvailableBefore = core.getAvailableUSDCLiquidity();
        console.log("CreditShaft USDC Liquidity Before: %s", creditShaftUsdcBefore / (10 ** USDC_DECIMALS));
        console.log("CreditShaft Available Balance Before: %s", creditShaftAvailableBefore / (10 ** USDC_DECIMALS));

        uint256 remainingUSDC = usdc.balanceOf(msg.sender);
        console.log("Remaining USDC Balance: %s", remainingUSDC / (10 ** USDC_DECIMALS));

        if (address(core.usdc()) == usdcToken && remainingUSDC > 0) {
            console.log("Adding %s USDC to CreditShaft Core...", remainingUSDC / (10 ** USDC_DECIMALS));
            usdc.approve(creditShaftCore, remainingUSDC);
            core.addUSDCLiquidity(remainingUSDC);
        } else if (address(core.usdc()) != usdcToken) {
            console.log("WARNING: CreditShaft uses different USDC token: %s", address(core.usdc()));
        }

        // Check CreditShaft liquidity after adding
        uint256 creditShaftUsdcAfter = core.getTotalUSDCLiquidity();
        uint256 creditShaftAvailableAfter = core.getAvailableUSDCLiquidity();
        console.log("CreditShaft USDC Liquidity After: %s", creditShaftUsdcAfter / (10 ** USDC_DECIMALS));
        console.log("CreditShaft Available Balance After: %s", creditShaftAvailableAfter / (10 ** USDC_DECIMALS));
        console.log(
            "CreditShaft Fees Accumulated: %s",
            (creditShaftAvailableAfter - creditShaftUsdcAfter) / (10 ** USDC_DECIMALS)
        );

        console.log("\n=== OVERALL LIQUIDITY SUMMARY ===\n");
        console.log("Total CreditShaft USDC: %s", creditShaftUsdcAfter / (10 ** USDC_DECIMALS));
        console.log("Total Pool Value: %s USDC", totalPoolValueUSDC / (10 ** USDC_DECIMALS));
        console.log("Combined Liquidity: %s USDC", (creditShaftUsdcAfter + totalPoolValueUSDC) / (10 ** USDC_DECIMALS));

        console.log("\n=== SETUP COMPLETE ===\n");
        console.log("[OK] Pool liquidity established with oracle price alignment");
        console.log("[OK] CreditShaft flash loan liquidity added");
        console.log("[OK] Ready for leveraged trading operations");
        console.log("=========================================");

        vm.stopBroadcast();
    }
}
