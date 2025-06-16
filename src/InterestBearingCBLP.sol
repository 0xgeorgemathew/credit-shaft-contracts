// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ICreditBridgeForLP
 * @dev A minimal interface for the CBLP token to communicate with the CreditBridge.
 * This prevents a circular dependency while allowing the token to query total assets.
 */
interface ICreditBridgeForLP {
    function totalLiquidity() external view returns (uint256);
}

/**
 * @title InterestBearingCBLP
 * @dev An interest-bearing token representing a share in the CreditBridge liquidity pool.
 * The value of each token increases as the CreditBridge accrues interest.
 * This contract follows a pattern similar to the ERC-4626 standard for tokenized vaults.
 */
contract InterestBearingCBLP is ERC20, Ownable {
    ICreditBridgeForLP public immutable creditBridge;

    constructor(address _creditBridge) ERC20("Interest Bearing CBLP", "ibCBLP") Ownable(msg.sender) {
        require(_creditBridge != address(0), "CreditBridge address cannot be zero");
        creditBridge = ICreditBridgeForLP(_creditBridge);
    }

    /**
     * @dev Returns the total amount of the underlying asset (ETH) held by the CreditBridge.
     */
    function totalAssets() public view returns (uint256) {
        return creditBridge.totalLiquidity();
    }

    /**
     * @dev Converts a specified amount of underlying assets to shares.
     * @param assets The amount of underlying assets.
     * @return shares The corresponding amount of shares.
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets; // 1:1 for the first deposit
        }
        return (assets * supply) / totalAssets();
    }

    /**
     * @dev Converts a specified amount of shares to the underlying asset value.
     * @param shares The amount of shares.
     * @return assets The corresponding amount of underlying assets.
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 0; // No shares exist, so their value is 0
        }
        return (shares * totalAssets()) / supply;
    }

    /**
     * @dev Mints shares to a user. Only callable by the CreditBridge contract (owner).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns shares from a user. Only callable by the CreditBridge contract (owner).
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
