// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IERC20, IFlashLoanReceiver} from "./interfaces/ISharedInterfaces.sol";

contract AaveStrategy is IFlashLoanReceiver {
    IPool public immutable aavePool;
    address public immutable creditShaftCore;
    address public immutable creditShaftLeverage;

    constructor(address _aavePool, address _creditShaftCore, address _creditShaftLeverage) {
        aavePool = IPool(_aavePool);
        creditShaftCore = _creditShaftCore;
        creditShaftLeverage = _creditShaftLeverage;
    }

    modifier onlyAuthorized() {
        require(msg.sender == creditShaftCore || msg.sender == creditShaftLeverage, "Only authorized contracts");
        _;
    }

    function supply(address asset, uint256 amount, address onBehalfOf) external onlyAuthorized {
        // Try transferFrom first, if that fails, assume tokens are already in contract
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        // Attempt to transfer from sender (works if they have approved us)
        try IERC20(asset).transferFrom(msg.sender, address(this), amount) {
            // Transfer successful
        } catch {
            // If transferFrom fails, check if we already have the tokens
            require(balanceBefore >= amount, "Insufficient token balance");
        }

        IERC20(asset).approve(address(aavePool), amount);
        aavePool.supply(asset, amount, onBehalfOf, 0);
    }

    function borrow(address asset, uint256 amount, address onBehalfOf) external onlyAuthorized {
        aavePool.borrow(asset, amount, 2, 0, onBehalfOf);
        IERC20(asset).transfer(msg.sender, amount);
    }

    function repay(address asset, uint256 amount, address onBehalfOf) external onlyAuthorized {
        // Try transferFrom first, if that fails, assume tokens are already in contract
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        // Attempt to transfer from sender (works if they have approved us)
        try IERC20(asset).transferFrom(msg.sender, address(this), amount) {
            // Transfer successful
        } catch {
            // If transferFrom fails, check if we already have the tokens
            require(balanceBefore >= amount, "Insufficient token balance");
        }

        IERC20(asset).approve(address(aavePool), amount);
        aavePool.repay(asset, amount, 2, onBehalfOf);
    }

    function withdraw(address asset, uint256 amount, address to) external onlyAuthorized returns (uint256) {
        return aavePool.withdraw(asset, amount, to);
    }

    function flashLoan(address asset, uint256 amount, bytes calldata params) external onlyAuthorized {
        aavePool.flashLoanSimple(address(this), asset, amount, params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(aavePool), "Invalid caller");
        require(initiator == address(this), "Invalid initiator");

        // Forward callback to CreditShaftCore
        IFlashLoanReceiver(creditShaftCore).executeOperation(assets, amounts, premiums, creditShaftCore, params);

        // Approve repayment
        uint256 repayAmount = amounts[0] + premiums[0];
        IERC20(assets[0]).approve(address(aavePool), repayAmount);

        return true;
    }

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return aavePool.getUserAccountData(user);
    }

    // Emergency function to transfer tokens back to core
    function emergencyTransfer(address asset, uint256 amount) external onlyAuthorized {
        IERC20(asset).transfer(creditShaftCore, amount);
    }
}
