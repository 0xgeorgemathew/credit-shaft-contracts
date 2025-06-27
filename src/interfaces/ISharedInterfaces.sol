// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface ICreditShaftCore {
    function provideFlashLoan(address recipient, address asset, uint256 amount, bytes calldata params) external;
    function receiveRewards(uint256 usdcAmount) external;
}

interface IAaveFaucet {
    function mint(address token, address to, uint256 amount) external returns (uint256);
}
