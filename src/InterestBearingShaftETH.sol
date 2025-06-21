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
}

/**
 * @title IInterestBearingShaftETH
 * @dev A minimal interface for the InterestBearingShaftETH token to communicate with the CreditShaft.
 */
interface IInterestBearingShaftETH {
    function totalLiquidity() external view returns (uint256);
    function getLiquidityIndex() external view returns (uint256);
}

/**
 * @title InterestBearingShaftETH
 * @dev An interest-bearing token similar to AAVE's aTokens.
 * Balances are stored as "shares" (scaled balances) and their real-time
 * value grows as interest accrues in the underlying pool.
 */
contract InterestBearingShaftETH is ERC20, Ownable {
    using WadRayMath for uint256;

    IInterestBearingShaftETH public immutable creditShaft;

    // Mapping from user to their shares (scaled balance in ray units)
    mapping(address => uint256) private _userShares;

    // Total shares (sum of all scaled balances)
    uint256 private _totalShares;

    // Events
    event Mint(address indexed user, uint256 shares, uint256 index);
    event Burn(address indexed user, uint256 shares, uint256 index);
    event BalanceTransfer(address indexed from, address indexed to, uint256 assetAmount, uint256 index);

    constructor(address _creditShaft) ERC20("Interest Bearing ShaftETH", "ShaftETH") Ownable(msg.sender) {
        require(_creditShaft != address(0), "CreditShaft address cannot be zero");
        creditShaft = IInterestBearingShaftETH(_creditShaft);
    }

    /**
     * @dev Returns the total amount of the underlying asset (ETH) held by the CreditShaft.
     * This represents the real-time value of all shares combined.
     */
    function totalAssets() public view returns (uint256) {
        return creditShaft.totalLiquidity();
    }

    /**
     * @notice Returns the shares (scaled balance) of a user.
     */
    function scaledBalanceOf(address user) external view returns (uint256) {
        return _userShares[user];
    }

    /**
     * @notice Returns the total shares (total scaled supply).
     */
    function scaledTotalSupply() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Returns the current liquidity index from CreditShaft.
     */
    function getLiquidityIndex() public view returns (uint256) {
        return creditShaft.getLiquidityIndex();
    }

    /**
     * @notice Returns the real-time balance of a user, which grows over time.
     * @dev This is calculated as: shares * liquidityIndex
     */
    function balanceOf(address user) public view override returns (uint256) {
        return _userShares[user].rayMul(getLiquidityIndex());
    }

    /**
     * @notice Returns the real-time total supply, which grows over time.
     * @dev This is calculated as: totalShares * liquidityIndex
     */
    function totalSupply() public view override returns (uint256) {
        return _totalShares.rayMul(getLiquidityIndex());
    }

    /**
     * @notice Converts a specified amount of underlying assets to shares.
     * @dev This is the inverse of a balance calculation: assets / liquidityIndex
     * @param assets The amount of underlying assets (e.g., ETH).
     * @return shares The corresponding amount of shares (scaled units).
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets.rayDiv(getLiquidityIndex());
    }

    /**
     * @notice Converts a specified amount of shares to the underlying asset value.
     * @dev This is a balance calculation: shares * liquidityIndex
     * @param shares The amount of shares (scaled units).
     * @return assets The corresponding amount of underlying assets (e.g., ETH).
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares.rayMul(getLiquidityIndex());
    }

    /**
     * @notice Mints shares to a user. Only callable by the CreditShaft contract (owner).
     * @param to The address to mint to.
     * @param shares The amount of shares (scaled amount) to mint.
     */
    function mint(address to, uint256 shares) external onlyOwner {
        uint256 index = getLiquidityIndex();

        _userShares[to] += shares;
        _totalShares += shares;

        emit Mint(to, shares, index);
        // Emit the standard ERC20 event with the asset value, not the share amount
        emit Transfer(address(0), to, shares.rayMul(index));
    }

    /**
     * @notice Burns shares from a user. Only callable by the CreditShaft contract (owner).
     * @param from The address to burn from.
     * @param shares The amount of shares (scaled amount) to burn.
     */
    function burn(address from, uint256 shares) external onlyOwner {
        require(_userShares[from] >= shares, "Insufficient shares");
        uint256 index = getLiquidityIndex();

        _userShares[from] -= shares;
        _totalShares -= shares;

        emit Burn(from, shares, index);
        // Emit the standard ERC20 event with the asset value, not the share amount
        emit Transfer(from, address(0), shares.rayMul(index));
    }

    /**
     * @dev Override transfer to handle scaled balances (shares).
     * The `amount` parameter is the asset value, which is converted to shares.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        _transferShares(owner, to, amount);
        return true;
    }

    /**
     * @dev Override transferFrom to handle scaled balances (shares).
     * The `amount` parameter is the asset value, which is converted to shares.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferShares(from, to, amount);
        return true;
    }

    /**
     * @dev Internal function to transfer shares based on an asset amount.
     */
    function _transferShares(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");

        uint256 index = getLiquidityIndex();
        uint256 sharesToTransfer = amount.rayDiv(index);

        require(_userShares[from] >= sharesToTransfer, "Insufficient balance");

        _userShares[from] -= sharesToTransfer;
        _userShares[to] += sharesToTransfer;

        emit BalanceTransfer(from, to, amount, index);
        emit Transfer(from, to, amount);
    }
}
