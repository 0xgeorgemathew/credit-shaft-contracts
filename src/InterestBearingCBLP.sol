// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WadRayMath
 * @dev Math library for fixed-point arithmetic with WAD and RAY precision
 * Based on AAVE's implementation
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;
    uint256 internal constant HALF_WAD = WAD / 2;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function ray() internal pure returns (uint256) {
        return RAY;
    }

    function wad() internal pure returns (uint256) {
        return WAD;
    }

    function halfRay() internal pure returns (uint256) {
        return HALF_RAY;
    }

    function halfWad() internal pure returns (uint256) {
        return HALF_WAD;
    }

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_WAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero");
        uint256 halfB = b / 2;
        return (a * WAD + halfB) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero");
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        return (a + halfRatio) / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }
}

/**
 * @title ICreditShaftForLP
 * @dev A minimal interface for the CBLP token to communicate with the CreditShaft.
 * This prevents a circular dependency while allowing the token to query total assets.
 */
interface ICreditShaftForLP {
    function totalLiquidity() external view returns (uint256);
    function totalInterestAccrued() external view returns (uint256);
    function getLiquidityIndex() external view returns (uint256);
}

/**
 * @title InterestBearingCBLP
 * @dev An interest-bearing token similar to AAVE's aTokens.
 * Balances grow in real-time as interest accrues in the underlying pool.
 * Uses ray math for precise interest calculations.
 */
contract InterestBearingCBLP is ERC20, Ownable {
    using WadRayMath for uint256;

    ICreditShaftForLP public immutable creditShaft;
    
    // Mapping from user to their scaled balance (principal in ray units)
    mapping(address => uint256) private _userScaledBalances;
    
    // Total scaled supply (sum of all scaled balances)
    uint256 private _totalScaledSupply;
    
    // Events
    event Mint(address indexed user, uint256 amount, uint256 index);
    event Burn(address indexed user, uint256 amount, uint256 index);
    event BalanceTransfer(address indexed from, address indexed to, uint256 amount, uint256 index);

    constructor(address _creditShaft) ERC20("Interest Bearing CBLP", "ibCBLP") Ownable(msg.sender) {
        require(_creditShaft != address(0), "CreditShaft address cannot be zero");
        creditShaft = ICreditShaftForLP(_creditShaft);
    }

    /**
     * @dev Returns the total amount of the underlying asset (ETH) held by the CreditShaft.
     */
    function totalAssets() public view returns (uint256) {
        return creditShaft.totalLiquidity();
    }

    /**
     * @dev Returns the scaled balance of a user
     */
    function scaledBalanceOf(address user) external view returns (uint256) {
        return _userScaledBalances[user];
    }

    /**
     * @dev Returns the total scaled supply
     */
    function scaledTotalSupply() external view returns (uint256) {
        return _totalScaledSupply;
    }

    /**
     * @dev Returns the current liquidity index from CreditShaft
     */
    function getLiquidityIndex() public view returns (uint256) {
        return creditShaft.getLiquidityIndex();
    }

    /**
     * @dev Returns the balance of a user, which grows over time based on the liquidity index
     * This is the AAVE-like behavior where balances increase automatically
     */
    function balanceOf(address user) public view override returns (uint256) {
        uint256 scaledBalance = _userScaledBalances[user];
        if (scaledBalance == 0) {
            return 0;
        }
        return scaledBalance.rayMul(getLiquidityIndex());
    }

    /**
     * @dev Returns the total supply, which grows over time based on the liquidity index
     */
    function totalSupply() public view override returns (uint256) {
        if (_totalScaledSupply == 0) {
            return 0;
        }
        return _totalScaledSupply.rayMul(getLiquidityIndex());
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
     * @dev Mints tokens to a user. Only callable by the CreditShaft contract (owner).
     * @param to The address to mint to
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        uint256 index = getLiquidityIndex();
        uint256 scaledAmount = amount.rayDiv(index);
        
        _userScaledBalances[to] += scaledAmount;
        _totalScaledSupply += scaledAmount;
        
        emit Mint(to, amount, index);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @dev Burns tokens from a user. Only callable by the CreditShaft contract (owner).
     * @param from The address to burn from
     * @param amount The amount to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        uint256 index = getLiquidityIndex();
        uint256 scaledAmount = amount.rayDiv(index);
        
        require(_userScaledBalances[from] >= scaledAmount, "Insufficient balance");
        
        _userScaledBalances[from] -= scaledAmount;
        _totalScaledSupply -= scaledAmount;
        
        emit Burn(from, amount, index);
        emit Transfer(from, address(0), amount);
    }

    /**
     * @dev Override transfer to handle scaled balances
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        _transferScaled(owner, to, amount);
        return true;
    }

    /**
     * @dev Override transferFrom to handle scaled balances
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferScaled(from, to, amount);
        return true;
    }

    /**
     * @dev Internal function to transfer scaled amounts
     */
    function _transferScaled(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        
        uint256 index = getLiquidityIndex();
        uint256 scaledAmount = amount.rayDiv(index);
        
        require(_userScaledBalances[from] >= scaledAmount, "Insufficient balance");
        
        _userScaledBalances[from] -= scaledAmount;
        _userScaledBalances[to] += scaledAmount;
        
        emit BalanceTransfer(from, to, amount, index);
        emit Transfer(from, to, amount);
    }

}