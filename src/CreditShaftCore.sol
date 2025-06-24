// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SimplifiedLPToken} from "./SimplifiedLPToken.sol";
import {IERC20, IFlashLoanReceiver} from "./interfaces/ISharedInterfaces.sol";

contract CreditShaftCore is Ownable, ReentrancyGuard {
    IERC20 public immutable usdc;
    SimplifiedLPToken public immutable lpToken;

    // Flash loan pool - simple USDC liquidity
    uint256 public totalUSDCLiquidity;
    uint256 public totalFlashLoanFees; // Accumulated fees for LPs

    // Events
    event USDCLiquidityProvided(address indexed lp, uint256 amount);
    event USDCLiquidityWithdrawn(address indexed lp, uint256 amount);
    event FlashLoanProvided(address indexed recipient, uint256 amount, uint256 premium);

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        lpToken = new SimplifiedLPToken("CreditShaft Core LP", "cscLP");
    }

    // USDC liquidity management for flash loans
    function addUSDCLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "No USDC provided");

        usdc.transferFrom(msg.sender, address(this), amount);

        // Calculate LP tokens including accumulated fees (makes tokens more valuable over time)
        uint256 totalPool = totalUSDCLiquidity + totalFlashLoanFees;
        uint256 lpTokensToMint;

        if (totalPool == 0) {
            lpTokensToMint = amount; // 1:1 for first deposit
        } else {
            lpTokensToMint = (amount * lpToken.totalSupply()) / totalPool;
        }

        lpToken.mint(msg.sender, lpTokensToMint);
        totalUSDCLiquidity += amount;

        emit USDCLiquidityProvided(msg.sender, amount);
    }

    function removeUSDCLiquidity(uint256 lpTokenAmount) external nonReentrant {
        require(lpTokenAmount > 0, "Invalid amount");
        require(lpToken.balanceOf(msg.sender) >= lpTokenAmount, "Insufficient LP tokens");

        // Calculate USDC amount including share of accumulated fees
        uint256 totalPool = totalUSDCLiquidity + totalFlashLoanFees;
        uint256 usdcAmount = (lpTokenAmount * totalPool) / lpToken.totalSupply();

        require(usdc.balanceOf(address(this)) >= usdcAmount, "Insufficient liquidity");

        lpToken.burn(msg.sender, lpTokenAmount);

        // Reduce from appropriate buckets
        if (usdcAmount <= totalFlashLoanFees) {
            totalFlashLoanFees -= usdcAmount;
        } else {
            uint256 fromFees = totalFlashLoanFees;
            uint256 fromLiquidity = usdcAmount - fromFees;
            totalFlashLoanFees = 0;
            totalUSDCLiquidity -= fromLiquidity;
        }

        usdc.transfer(msg.sender, usdcAmount);

        emit USDCLiquidityWithdrawn(msg.sender, usdcAmount);
    }

    function provideFlashLoan(address recipient, address asset, uint256 amount, bytes calldata params) external {
        require(asset == address(usdc), "Only USDC flash loans supported");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient liquidity");

        uint256 premium = (amount * 9) / 10000; // 0.09% fee

        // Transfer funds to recipient
        usdc.transfer(recipient, amount);

        // Call recipient's callback
        IFlashLoanReceiver(recipient).executeOperation(
            _asSingletonArray(asset), _asSingletonArray(amount), _asSingletonArray(premium), msg.sender, params
        );

        // Collect repayment + premium
        uint256 repayAmount = amount + premium;
        require(usdc.balanceOf(address(this)) >= repayAmount, "Flash loan not repaid");

        // Add premium to fees (benefits LP holders)
        totalFlashLoanFees += premium;

        emit FlashLoanProvided(recipient, amount, premium);
    }

    // Utility functions
    function _asSingletonArray(address element) private pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;
        return array;
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;
        return array;
    }

    // View functions
    function getAvailableUSDCLiquidity() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getTotalUSDCLiquidity() external view returns (uint256) {
        return totalUSDCLiquidity;
    }

    function receiveRewards(uint256 usdcAmount) external {
        require(usdcAmount > 0, "No rewards to receive");

        // Add received rewards to flash loan fees (benefits LP holders)
        totalFlashLoanFees += usdcAmount;
    }
}
