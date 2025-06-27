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

    constructor(address _usdc, address _lpToken) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        lpToken = SimplifiedLPToken(_lpToken);
    }

    function addUSDCLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "No USDC provided");
        usdc.transferFrom(msg.sender, address(this), amount);
        uint256 totalPool = totalUSDCLiquidity + totalFlashLoanFees;
        uint256 lpTokensToMint = (totalPool == 0) ? amount : (amount * lpToken.totalSupply()) / totalPool;
        lpToken.mint(msg.sender, lpTokensToMint);
        totalUSDCLiquidity += amount;
        emit USDCLiquidityProvided(msg.sender, amount);
    }

    function removeUSDCLiquidity(uint256 lpTokenAmount) external nonReentrant {
        require(lpTokenAmount > 0, "Invalid amount");
        require(lpToken.balanceOf(msg.sender) >= lpTokenAmount, "Insufficient LP tokens");
        uint256 totalPool = totalUSDCLiquidity + totalFlashLoanFees;
        uint256 usdcAmount = (lpTokenAmount * totalPool) / lpToken.totalSupply();
        require(usdc.balanceOf(address(this)) >= usdcAmount, "Insufficient liquidity");
        lpToken.burn(msg.sender, lpTokenAmount);
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

    // --- THE CORRECTED FLASH LOAN FUNCTION ---
    function provideFlashLoan(address recipient, address asset, uint256 amount, bytes calldata params)
        external
        nonReentrant
    {
        require(asset == address(usdc), "Only USDC flash loans supported");
        uint256 balanceBefore = usdc.balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient liquidity");

        uint256 premium = (amount * 9) / 10000; // 0.09% fee

        // 1. Transfer funds to recipient
        usdc.transfer(recipient, amount);

        // 2. Call recipient's callback. The 'initiator' should be this contract.
        IFlashLoanReceiver(recipient).executeOperation(
            _asSingletonArray(asset), _asSingletonArray(amount), _asSingletonArray(premium), recipient, params
        );

        // 3. **THE FIX:** Actively pull the funds back from the recipient.
        // This will succeed because the recipient approved this contract in its executeOperation.
        uint256 repayAmount = amount + premium;
        usdc.transferFrom(recipient, address(this), repayAmount);

        // 4. (Good Practice) Final sanity check to ensure everything was returned correctly.
        require(usdc.balanceOf(address(this)) >= balanceBefore + premium, "Flash loan not fully repaid");

        // 5. Add premium to fees for LPs
        totalFlashLoanFees += premium;

        emit FlashLoanProvided(recipient, amount, premium);
    }

    // --- Utility and View functions are fine ---

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

    function getAvailableUSDCLiquidity() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getTotalUSDCLiquidity() external view returns (uint256) {
        return totalUSDCLiquidity;
    }

    function receiveRewards(uint256 usdcAmount) external {
        require(usdcAmount > 0, "No rewards to receive");
        totalFlashLoanFees += usdcAmount;
    }
}
