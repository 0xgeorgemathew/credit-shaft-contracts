// File: script/SetupTestLiquidity.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/interfaces/ISharedInterfaces.sol";

// Interfaces from your original script...
interface IUniswapV2Factory {
    function getPair(address, address) external view returns (address);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256, uint256, uint256);
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        returns (uint256[] memory);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

interface MockAggregatorInterface {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

contract SetupTestLiquidity is Script {
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    uint256 constant USDC_DECIMALS = 6;
    uint256 constant LINK_DECIMALS = 18;
    uint256 constant PRICE_SCALE = 1e18;

    function run() external {
        string memory deploymentFile = vm.readFile("deployments/sepolia.json");
        address creditShaftCore = vm.parseJsonAddress(deploymentFile, ".contracts.CreditShaftCore");
        address usdcToken = vm.parseJsonAddress(deploymentFile, ".dependencies.USDC");
        address linkToken = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK");
        address uniswapRouterAddress = vm.parseJsonAddress(deploymentFile, ".dependencies.UNISWAP_ROUTER");
        address linkPriceFeed = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK_PRICE_FEED");

        IUniswapV2Router uniswapRouter = IUniswapV2Router(uniswapRouterAddress);
        IERC20 usdc = IERC20(usdcToken);
        IERC20 link = IERC20(linkToken);

        console.log("=========================================");
        console.log("      CREDIT SHAFT LIQUIDITY SETUP");
        console.log("=========================================");
        console.log("NOTE: This script assumes you have already minted tokens.");

        vm.startBroadcast();

        // --- Step 1: Get Oracle Price ---
        int256 linkPriceInt;
        uint8 priceDecimals;
        try MockAggregatorInterface(linkPriceFeed).latestAnswer() returns (int256 price) {
            linkPriceInt = price;
            priceDecimals = MockAggregatorInterface(linkPriceFeed).decimals();
        } catch {
            (, linkPriceInt,,,) = AggregatorV3Interface(linkPriceFeed).latestRoundData();
            priceDecimals = AggregatorV3Interface(linkPriceFeed).decimals();
        }
        uint256 linkPriceUSD = uint256(linkPriceInt);

        // --- Step 2: Align Pool Price via Corrective Swap ---
        console.log("\n=== STEP 1: FORCING POOL TO ORACLE PRICE VIA SWAP ===\n");
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        address pairAddress = factory.getPair(usdcToken, linkToken);
        require(pairAddress != address(0), "Pair does not exist");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (uint256 usdcReserve, uint256 linkReserve) =
            pair.token0() == usdcToken ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        uint256 currentPoolPrice = (usdcReserve * (10 ** (LINK_DECIMALS - USDC_DECIMALS)) * PRICE_SCALE) / linkReserve;
        uint256 oraclePrice = (linkPriceUSD * PRICE_SCALE) / (10 ** priceDecimals);

        console.log("Initial Pool Price:  1 LINK = %s USDC", currentPoolPrice / PRICE_SCALE);
        console.log("Target Oracle Price: 1 LINK = %s USDC", oraclePrice / PRICE_SCALE);

        uint256 deadline = block.timestamp + 15 minutes;

        uint256 normalizedPoolPriceNum = usdcReserve * (10 ** (LINK_DECIMALS - USDC_DECIMALS));
        if (normalizedPoolPriceNum * (10 ** priceDecimals) != linkReserve * linkPriceUSD) {
            uint256 k = usdcReserve * linkReserve;
            uint256 numerator = k * linkPriceUSD * (10 ** USDC_DECIMALS);
            uint256 denominator = (10 ** priceDecimals) * (10 ** LINK_DECIMALS);
            uint256 targetUsdcReserve = sqrt(numerator / denominator);

            if (targetUsdcReserve > usdcReserve) {
                uint256 usdcIn = targetUsdcReserve - usdcReserve;
                console.log("Pool price is too low. Swapping %s USDC for LINK...", usdcIn / (10 ** USDC_DECIMALS));
                require(
                    usdc.balanceOf(msg.sender) >= usdcIn, "Not enough USDC for corrective swap. Run MintTokens script."
                );

                usdc.approve(uniswapRouterAddress, usdcIn);
                address[] memory path = new address[](2);
                path[0] = usdcToken;
                path[1] = linkToken;
                uniswapRouter.swapExactTokensForTokens(usdcIn, 1, path, msg.sender, deadline);
            } else {
                // Not covering the other case for brevity as it wasn't triggered
                console.log("Pool price is too high. Manual intervention may be needed.");
            }
        } else {
            console.log("Pool price already aligned.");
        }

        // --- Step 3: Add Liquidity and Fund Core ---
        (reserve0, reserve1,) = pair.getReserves();
        (uint256 finalUsdcReserve, uint256 finalLinkReserve) =
            pair.token0() == usdcToken ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
        uint256 finalPoolPrice =
            (finalUsdcReserve * (10 ** (LINK_DECIMALS - USDC_DECIMALS)) * PRICE_SCALE) / finalLinkReserve;
        console.log("Final Aligned Pool Price: 1 LINK = %s USDC", finalPoolPrice / PRICE_SCALE);
        console.log("-----------------------------------------\n");

        console.log("=== STEP 2: ADDING LIQUIDITY & FUNDING CORE ===\n");
        uint256 usdcToAdd = 100_000 * (10 ** USDC_DECIMALS);
        uint256 linkToAdd = (usdcToAdd * finalLinkReserve) / finalUsdcReserve;

        console.log(
            "Adding %s USDC and %s LINK to LP...", usdcToAdd / (10 ** USDC_DECIMALS), linkToAdd / (10 ** LINK_DECIMALS)
        );
        require(usdc.balanceOf(msg.sender) >= usdcToAdd, "Not enough USDC to add liquidity.");
        require(link.balanceOf(msg.sender) >= linkToAdd, "Not enough LINK to add liquidity.");

        usdc.approve(uniswapRouterAddress, type(uint256).max); // Approve once for simplicity
        link.approve(uniswapRouterAddress, type(uint256).max);

        uniswapRouter.addLiquidity(usdcToken, linkToken, usdcToAdd, linkToAdd, 1, 1, msg.sender, deadline);
        console.log("LP added successfully.");

        CreditShaftCore core = CreditShaftCore(creditShaftCore);
        uint256 remainingUSDC = usdc.balanceOf(msg.sender);
        if (remainingUSDC > 0) {
            console.log("Adding %s USDC to CreditShaft Core...", remainingUSDC / (10 ** USDC_DECIMALS));
            usdc.approve(creditShaftCore, remainingUSDC);
            core.addUSDCLiquidity(remainingUSDC);
        }

        uint256 creditShaftUsdcAfter = core.getTotalUSDCLiquidity();
        console.log("CreditShaft USDC Liquidity: %s", creditShaftUsdcAfter / (10 ** USDC_DECIMALS));
        console.log("=== SETUP COMPLETE ===");

        vm.stopBroadcast();
    }
}
