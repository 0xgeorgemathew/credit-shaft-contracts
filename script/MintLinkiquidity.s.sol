// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

interface IAaveFaucet {
    function mint(address token, address to, uint256 amount) external returns (uint256);
}

contract MintLinkLiquidity is Script {
    IAaveFaucet constant AAVE_FAUCET = IAaveFaucet(0xBCcD21ae43139bEF545e72e20E78f039A3Ac1b96);

    function run() external {
        string memory deploymentFile = vm.readFile("deployments/sepolia.json");
        address linkToken = vm.parseJsonAddress(deploymentFile, ".dependencies.LINK");

        vm.startBroadcast();

        uint256 totalAmountToMint = 100_000;
        uint256 faucetMintLimit = 10_000;

        for (uint256 i = 0; i < totalAmountToMint / faucetMintLimit; i++) {
            AAVE_FAUCET.mint(linkToken, msg.sender, faucetMintLimit * 10 ** 18);
        }

        vm.stopBroadcast();
    }
}
