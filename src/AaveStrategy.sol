// Filename: src/AaveStrategy.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IERC20, IFlashLoanReceiver, ICreditShaftCore} from "./interfaces/ISharedInterfaces.sol";

contract AaveStrategy is IFlashLoanReceiver {
    IPool public immutable aavePool;
    address public immutable creditShaftCore;
    address public immutable creditShaftLeverage;

    constructor(address _aavePool, address _creditShaftCore, address _creditShaftLeverage) {
        aavePool = IPool(_aavePool);
        creditShaftCore = _creditShaftCore;
        creditShaftLeverage = _creditShaftLeverage;
    }

    modifier onlyLeverageContract() {
        require(msg.sender == creditShaftLeverage, "Only leverage contract");
        _;
    }

    // FINAL CORRECTED SUPPLY
    // The AaveStrategy contract will be the owner of the collateral.
    function supply(address asset, uint256 amount) external onlyLeverageContract {
        // 1. Pull tokens from CreditShaftLeverage to this strategy contract.
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // 2. Approve the Aave Pool to take the tokens from THIS contract.
        IERC20(asset).approve(address(aavePool), amount);
        // 3. Supply to Aave. THIS contract becomes the owner of the aTokens.
        aavePool.supply(asset, amount, address(this), 0);
    }

    // FINAL CORRECTED BORROW
    // The AaveStrategy contract borrows against its own collateral and forwards the funds.
    function borrow(address asset, uint256 amount) external onlyLeverageContract {
        // 1. Borrow from Aave. The debt is assigned to THIS contract, and funds are sent to THIS contract.
        aavePool.borrow(asset, amount, 2, 0, address(this));
        // 2. CRITICAL FIX: Forward the borrowed funds to CreditShaftLeverage.
        IERC20(asset).transfer(creditShaftLeverage, amount);
    }

    // FINAL CORRECTED REPAY
    // CreditShaftLeverage sends funds to this contract to repay THIS contract's debt.
    function repay(address asset, uint256 amount) external onlyLeverageContract {
        // 1. Pull funds from CreditShaftLeverage to this strategy contract.
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // 2. Approve the Aave Pool to take the funds from THIS contract.
        IERC20(asset).approve(address(aavePool), amount);
        // 3. Repay the debt held by THIS contract.
        aavePool.repay(asset, amount, 2, address(this));
    }

    // FINAL CORRECTED WITHDRAW
    // Withdraws collateral owned by this contract and sends it to CreditShaftLeverage.
    function withdraw(address asset, uint256 amount) external onlyLeverageContract returns (uint256) {
        // Withdraws from THIS contract's position and sends to the specified address 'creditShaftLeverage'.
        return aavePool.withdraw(asset, amount, creditShaftLeverage);
    }

    // --- No changes needed for flash loan or view functions ---

    function getUserAccountData() external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return aavePool.getUserAccountData(address(this));
    }

    // Unused in this flow but good practice to keep
    function executeOperation(address[] calldata, uint256[] calldata, uint256[] calldata, address, bytes calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}
