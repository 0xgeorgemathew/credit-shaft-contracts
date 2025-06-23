// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CreditShaftCore.sol";
import "../src/interfaces/ISharedInterfaces.sol";

interface IAaveFaucet {
    function mint(address token, address to, uint256 amount) external returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

contract SetupTestLiquidity is Script {
    IAaveFaucet constant AAVE_FAUCET = IAaveFaucet(0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D);
    IUniswapV2Router constant UNISWAP_ROUTER = IUniswapV2Router(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    AggregatorV3Interface constant LINK_USD_PRICE_FEED =
        AggregatorV3Interface(0xc59E3633BAAC79493d908e63626716e204A45EdF);

    address constant LINK_TOKEN = 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5;
    address constant USDC_TOKEN = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant LINK_DECIMALS = 18;

    function run() external {
        address creditShaftCore = vm.envOr("CREDIT_SHAFT_CORE", address(0));
        require(creditShaftCore != address(0), "CREDIT_SHAFT_CORE address required");

        vm.startBroadcast();

        (, int256 linkPriceInt,,,) = LINK_USD_PRICE_FEED.latestRoundData();
        uint8 priceDecimals = LINK_USD_PRICE_FEED.decimals();
        uint256 linkPriceUSD = uint256(linkPriceInt);

        uint256 usdcAmount = 10000 * 10 ** USDC_DECIMALS;
        AAVE_FAUCET.mint(USDC_TOKEN, msg.sender, usdcAmount);

        uint256 linkAmount = 10000 * 10 ** LINK_DECIMALS;
        AAVE_FAUCET.mint(LINK_TOKEN, msg.sender, linkAmount);

        address pair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(USDC_TOKEN, LINK_TOKEN);

        uint256 usdcLiquidity;
        uint256 linkLiquidity;

        if (pair != address(0) && IUniswapV2Pair(pair).token0() != address(0)) {
            IUniswapV2Pair existingPair = IUniswapV2Pair(pair);
            (uint112 existingReserve0, uint112 existingReserve1,) = existingPair.getReserves();
            address existingToken0 = existingPair.token0();

            uint256 existingUsdcReserve;
            uint256 existingLinkReserve;

            if (existingToken0 == USDC_TOKEN) {
                existingUsdcReserve = uint256(existingReserve0);
                existingLinkReserve = uint256(existingReserve1);
            } else {
                existingUsdcReserve = uint256(existingReserve1);
                existingLinkReserve = uint256(existingReserve0);
            }

            if (existingUsdcReserve > 0 && existingLinkReserve > 0) {
                usdcLiquidity = 5000 * 10 ** USDC_DECIMALS;
                linkLiquidity = (usdcLiquidity * existingLinkReserve) / existingUsdcReserve;
            } else {
                // Handle case where pair exists but has no liquidity
                usdcLiquidity = 5000 * 10 ** USDC_DECIMALS;
                linkLiquidity = (usdcLiquidity * 10 ** (LINK_DECIMALS + priceDecimals - USDC_DECIMALS)) / linkPriceUSD;
            }

            if (linkLiquidity > linkAmount) {
                linkLiquidity = linkAmount;
                usdcLiquidity = (linkLiquidity * existingUsdcReserve) / existingLinkReserve;
            }
        } else {
            usdcLiquidity = 5000 * 10 ** USDC_DECIMALS;
            // Normalize price calculation to avoid precision loss
            linkLiquidity = (usdcLiquidity * 10 ** (LINK_DECIMALS + priceDecimals - USDC_DECIMALS)) / linkPriceUSD;

            if (linkLiquidity > linkAmount) {
                linkLiquidity = linkAmount;
                usdcLiquidity = (linkLiquidity * linkPriceUSD) / 10 ** (LINK_DECIMALS + priceDecimals - USDC_DECIMALS);
            }
        }

        IERC20 usdc = IERC20(USDC_TOKEN);
        IERC20 link = IERC20(LINK_TOKEN);

        usdc.approve(address(UNISWAP_ROUTER), usdcLiquidity);
        link.approve(address(UNISWAP_ROUTER), linkLiquidity);

        UNISWAP_ROUTER.addLiquidity(
            USDC_TOKEN,
            LINK_TOKEN,
            usdcLiquidity,
            linkLiquidity,
            usdcLiquidity * 95 / 100,
            linkLiquidity * 95 / 100,
            msg.sender,
            block.timestamp + 300
        );

        address finalPair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(USDC_TOKEN, LINK_TOKEN);
        IUniswapV2Pair finalPairContract = IUniswapV2Pair(finalPair);
        (uint112 finalReserve0, uint112 finalReserve1,) = finalPairContract.getReserves();
        address finalToken0 = finalPairContract.token0();

        uint256 finalUsdcReserve;
        uint256 finalLinkReserve;

        if (finalToken0 == USDC_TOKEN) {
            finalUsdcReserve = uint256(finalReserve0);
            finalLinkReserve = uint256(finalReserve1);
        } else {
            finalUsdcReserve = uint256(finalReserve1);
            finalLinkReserve = uint256(finalReserve0);
        }

        require(finalLinkReserve > 0, "Pool has no LINK reserves");

        // --- FIX STARTS HERE ---

        // Calculate the price of 1 full LINK token in "USDC-wei" (scaled by 10**6)
        // Formula: (USDC reserves * 10^18) / LINK reserves
        uint256 poolPriceScaled = (finalUsdcReserve * (10 ** LINK_DECIMALS)) / finalLinkReserve;

        // For logging, we need to show dollars and cents.
        // The integer part is poolPriceScaled / 10**6
        // The fractional part is what's left over. We'll show 2 decimal places.
        uint256 usdcPriceInteger = poolPriceScaled / (10 ** USDC_DECIMALS);
        uint256 usdcPriceFractional = (poolPriceScaled % (10 ** USDC_DECIMALS)) / 10 ** (USDC_DECIMALS - 2);

        console.log("Pool Price: 1 LINK = %s.%s USDC", usdcPriceInteger, usdcPriceFractional);

        // Similarly for Chainlink price for consistency
        uint256 clPriceInteger = linkPriceUSD / (10 ** priceDecimals);
        uint256 clPriceFractional = (linkPriceUSD % (10 ** priceDecimals)) / 10 ** (priceDecimals - 2);

        console.log("Chainlink Price: 1 LINK = $%s.%s", clPriceInteger, clPriceFractional);

        // --- FIX ENDS HERE ---

        CreditShaftCore core = CreditShaftCore(creditShaftCore);
        address coreUsdcToken = address(core.usdc());

        if (coreUsdcToken == USDC_TOKEN) {
            uint256 remainingUSDC = usdc.balanceOf(msg.sender);
            if (remainingUSDC > 0) {
                usdc.approve(creditShaftCore, remainingUSDC);
                core.addUSDCLiquidity(remainingUSDC);
            }
        }

        vm.stopBroadcast();
    }
}
