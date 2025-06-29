// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// --- INTERFACES ---
interface IUniswapV2Router {
    function factory() external pure returns (address);
    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SetupTestLiquidity is Script {
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant LINK_DECIMALS = 18;

    function run() external {
        string memory deploymentFile = vm.readFile("deployments/sepolia.json");
        address usdcToken = vm.parseJsonAddress(deploymentFile, ".dependencies.USDC");
        address linkToken = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK");
        address uniswapRouterAddress = vm.parseJsonAddress(deploymentFile, ".dependencies.UNISWAP_ROUTER");

        IUniswapV2Router uniswapRouter = IUniswapV2Router(uniswapRouterAddress);
        IERC20 usdc = IERC20(usdcToken);
        IERC20 link = IERC20(linkToken);

        console.log("==================================================");
        console.log("   ADD MORE LIQUIDITY SCRIPT");
        console.log("==================================================");

        vm.startBroadcast();
        uint256 deadline = block.timestamp + 15 minutes;

        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        address pairAddress = factory.getPair(usdcToken, linkToken);
        require(pairAddress != address(0), "Pair must exist to add liquidity.");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        console.log("\n-> Adding more liquidity by respecting the current pool price.");

        // Step 1: Get the actual, real-time reserves from the pool
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (uint256 reserveUsdc, uint256 reserveLink) =
            pair.token0() == usdcToken ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        uint256 currentPrice = (reserveUsdc * (10 ** LINK_DECIMALS)) / (reserveLink * (10 ** USDC_DECIMALS));
        console.log("   Current Pool Price: 1 LINK = %s USDC", currentPrice);

        // Step 2: Decide how much of our primary asset (USDC) to add.
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        require(usdcBalance > 1 * (10 ** USDC_DECIMALS), "Not enough USDC to add more liquidity.");
        uint256 usdcForPool = usdcBalance * 95 / 100;

        // Step 3: Calculate the EXACT amount of LINK needed based on the current reserves.
        // This is the canonical formula: amountB = (amountA * reserveB) / reserveA
        uint256 linkForPool = (usdcForPool * reserveLink) / reserveUsdc;

        uint256 linkBalance = link.balanceOf(msg.sender);
        require(linkBalance >= linkForPool, "Not enough LINK for this deposit.");
        console.log(
            "   To match the pool's price, we will add %s USDC and %s LINK.", usdcForPool / 1e6, linkForPool / 1e18
        );

        // Step 4: Add the liquidity with a safe slippage tolerance.
        usdc.approve(uniswapRouterAddress, usdcForPool);
        link.approve(uniswapRouterAddress, linkForPool);

        (uint256 usdcAdded, uint256 linkAdded,) = uniswapRouter.addLiquidity(
            usdcToken,
            linkToken,
            usdcForPool,
            linkForPool,
            usdcForPool * 99 / 100, // 1% slippage is safe because our ratio is now perfect.
            linkForPool * 99 / 100,
            msg.sender,
            deadline
        );
        console.log("   Success! Added %s USDC and %s LINK.", usdcAdded / 1e6, linkAdded / 1e18);

        // --- FINAL REPORT ---
        (r0, r1,) = pair.getReserves();
        (reserveUsdc, reserveLink) =
            pair.token0() == usdcToken ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 finalPoolPrice = (reserveUsdc * (10 ** LINK_DECIMALS)) / (reserveLink * (10 ** USDC_DECIMALS));

        console.log("\n=================== FINAL STATUS ===================");
        console.log("Final Pool Price:      1 LINK = %s USDC", finalPoolPrice);
        console.log("Your remaining USDC:   %s", usdc.balanceOf(msg.sender) / 1e6);
        console.log("Your remaining LINK:   %s", link.balanceOf(msg.sender) / 1e18);
        console.log("==================================================");

        vm.stopBroadcast();
    }
}
