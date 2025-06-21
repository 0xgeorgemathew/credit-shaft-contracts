# CreditShaft Frontend Integration Guide

## Overview

CreditShaft is a DeFi lending protocol that allows users to borrow ETH using credit card pre-authorizations as collateral. This guide covers frontend integration using the simplified contract functions.

## Simplified Contract Functions

### Core Functions

#### `borrowETH()`
Creates a new loan with credit card pre-authorization.

```solidity
function borrowETH(
    uint256 preAuthAmountUSD,
    uint256 preAuthDurationMinutes,
    string memory stripePaymentIntentId,
    string memory stripeCustomerId,
    string memory stripePaymentMethodId
) external returns (uint256 loanId)
```

#### `repayLoan()`
Repays the user's loan (auto-detects and calculates amount).

```solidity
function repayLoan() external payable
```

#### `addLiquidity()`
Add ETH to the lending pool.

```solidity
function addLiquidity() external payable
```

#### `removeLiquidity()`
Remove liquidity by burning LP tokens.

```solidity
function removeLiquidity(uint256 shares) external
```

### Simplified Getter Functions

#### `getRepayAmount()`
Returns exact amount needed to repay loan (0 if no loan).

```solidity
function getRepayAmount() external view returns (uint256)
```

#### `hasActiveLoan()`
Simple boolean check for active loans.

```solidity
function hasActiveLoan() external view returns (bool)
```

#### `getLoanInfo()`
Returns loan details in a simple format.

```solidity
function getLoanInfo() external view returns (
    uint256 principal,
    uint256 interest,
    uint256 total,
    bool expired
)
```

#### `getMyLPBalance()`
Returns LP token balance and ETH value.

```solidity
function getMyLPBalance() external view returns (
    uint256 shares,
    uint256 value
)
```

#### `getPoolStats()`
Returns pool statistics.

```solidity
function getPoolStats() external view returns (
    uint256 totalLiquidity,
    uint256 totalBorrowed,
    uint256 available,
    uint256 utilization
)
```

## Next.js Integration

### 1. Contract Setup

```typescript
import { ethers } from 'ethers';

const CREDITSHAFT_ABI = [
  "function borrowETH(uint256,uint256,string,string,string) external returns (uint256)",
  "function repayLoan() external payable",
  "function addLiquidity() external payable",
  "function removeLiquidity(uint256) external",
  "function getRepayAmount() external view returns (uint256)",
  "function hasActiveLoan() external view returns (bool)",
  "function getLoanInfo() external view returns (uint256,uint256,uint256,bool)",
  "function getMyLPBalance() external view returns (uint256,uint256)",
  "function getPoolStats() external view returns (uint256,uint256,uint256,uint256)"
];

const CONTRACT_ADDRESS = "YOUR_DEPLOYED_CONTRACT_ADDRESS";

const getContract = () => {
  const provider = new ethers.providers.Web3Provider(window.ethereum);
  const signer = provider.getSigner();
  return new ethers.Contract(CONTRACT_ADDRESS, CREDITSHAFT_ABI, signer);
};
```

### 2. React Hooks

#### Loan Status Hook

```typescript
import { useState, useEffect } from 'react';

interface LoanInfo {
  hasLoan: boolean;
  principal: string;
  interest: string;
  total: string;
  expired: boolean;
  repayAmount: string;
}

export const useLoanStatus = () => {
  const [loanInfo, setLoanInfo] = useState<LoanInfo | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchLoanStatus = async () => {
    try {
      setLoading(true);
      const contract = getContract();
      
      const hasLoan = await contract.hasActiveLoan();
      
      if (hasLoan) {
        const [principal, interest, total, expired] = await contract.getLoanInfo();
        const repayAmount = await contract.getRepayAmount();
        
        setLoanInfo({
          hasLoan: true,
          principal: ethers.utils.formatEther(principal),
          interest: ethers.utils.formatEther(interest),
          total: ethers.utils.formatEther(total),
          expired,
          repayAmount: ethers.utils.formatEther(repayAmount)
        });
      } else {
        setLoanInfo({
          hasLoan: false,
          principal: '0',
          interest: '0',
          total: '0',
          expired: false,
          repayAmount: '0'
        });
      }
    } catch (error) {
      console.error('Error fetching loan status:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLoanStatus();
  }, []);

  return { loanInfo, loading, refetch: fetchLoanStatus };
};
```

#### LP Balance Hook

```typescript
export const useLPBalance = () => {
  const [balance, setBalance] = useState({ shares: '0', value: '0' });
  const [loading, setLoading] = useState(true);

  const fetchBalance = async () => {
    try {
      setLoading(true);
      const contract = getContract();
      const [shares, value] = await contract.getMyLPBalance();
      
      setBalance({
        shares: ethers.utils.formatEther(shares),
        value: ethers.utils.formatEther(value)
      });
    } catch (error) {
      console.error('Error fetching LP balance:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBalance();
  }, []);

  return { balance, loading, refetch: fetchBalance };
};
```

#### Pool Stats Hook

```typescript
export const usePoolStats = () => {
  const [stats, setStats] = useState({
    totalLiquidity: '0',
    totalBorrowed: '0',
    available: '0',
    utilization: '0'
  });
  const [loading, setLoading] = useState(true);

  const fetchStats = async () => {
    try {
      setLoading(true);
      const contract = getContract();
      const [totalLiq, totalBorr, available, utilization] = await contract.getPoolStats();
      
      setStats({
        totalLiquidity: ethers.utils.formatEther(totalLiq),
        totalBorrowed: ethers.utils.formatEther(totalBorr),
        available: ethers.utils.formatEther(available),
        utilization: (utilization.toNumber() / 100).toString() // Convert from basis points
      });
    } catch (error) {
      console.error('Error fetching pool stats:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStats();
  }, []);

  return { stats, loading, refetch: fetchStats };
};
```

### 3. Transaction Functions

#### Borrow ETH

```typescript
interface BorrowParams {
  preAuthAmountUSD: number;
  preAuthDurationMinutes: number;
  stripePaymentIntentId: string;
  stripeCustomerId: string;
  stripePaymentMethodId: string;
}

export const borrowETH = async (params: BorrowParams) => {
  try {
    const contract = getContract();
    
    const tx = await contract.borrowETH(
      params.preAuthAmountUSD,
      params.preAuthDurationMinutes,
      params.stripePaymentIntentId,
      params.stripeCustomerId,
      params.stripePaymentMethodId
    );
    
    return await tx.wait();
  } catch (error) {
    console.error('Error borrowing ETH:', error);
    throw error;
  }
};
```

#### Repay Loan

```typescript
export const repayLoan = async () => {
  try {
    const contract = getContract();
    
    // Get exact repayment amount
    const repayAmount = await contract.getRepayAmount();
    
    if (repayAmount.eq(0)) {
      throw new Error('No loan to repay');
    }
    
    const tx = await contract.repayLoan({
      value: repayAmount
    });
    
    return await tx.wait();
  } catch (error) {
    console.error('Error repaying loan:', error);
    throw error;
  }
};
```

#### Add Liquidity

```typescript
export const addLiquidity = async (ethAmount: string) => {
  try {
    const contract = getContract();
    
    const tx = await contract.addLiquidity({
      value: ethers.utils.parseEther(ethAmount)
    });
    
    return await tx.wait();
  } catch (error) {
    console.error('Error adding liquidity:', error);
    throw error;
  }
};
```

#### Remove Liquidity

```typescript
export const removeLiquidity = async (shares: string) => {
  try {
    const contract = getContract();
    
    const tx = await contract.removeLiquidity(
      ethers.utils.parseEther(shares)
    );
    
    return await tx.wait();
  } catch (error) {
    console.error('Error removing liquidity:', error);
    throw error;
  }
};
```

### 4. UI Components

#### Loan Dashboard

```tsx
import React from 'react';
import { useLoanStatus } from './hooks';

export const LoanDashboard: React.FC = () => {
  const { loanInfo, loading, refetch } = useLoanStatus();

  if (loading) return <div>Loading...</div>;

  if (!loanInfo?.hasLoan) {
    return (
      <div className="loan-dashboard">
        <h2>No Active Loan</h2>
        <p>You can borrow ETH using your credit card as collateral.</p>
        <button onClick={() => {/* Open borrow modal */}}>
          Borrow ETH
        </button>
      </div>
    );
  }

  return (
    <div className="loan-dashboard">
      <h2>Your Active Loan</h2>
      <div className="loan-details">
        <div className="detail-item">
          <label>Principal:</label>
          <span>{loanInfo.principal} ETH</span>
        </div>
        <div className="detail-item">
          <label>Interest:</label>
          <span>{loanInfo.interest} ETH</span>
        </div>
        <div className="detail-item">
          <label>Total to Repay:</label>
          <span>{loanInfo.total} ETH</span>
        </div>
        <div className="detail-item">
          <label>Status:</label>
          <span className={loanInfo.expired ? 'expired' : 'active'}>
            {loanInfo.expired ? 'Expired' : 'Active'}
          </span>
        </div>
      </div>
      
      <button 
        onClick={async () => {
          await repayLoan();
          refetch();
        }}
        className="repay-button"
      >
        Repay Loan ({loanInfo.repayAmount} ETH)
      </button>
    </div>
  );
};
```

#### LP Dashboard

```tsx
import React, { useState } from 'react';
import { useLPBalance, usePoolStats } from './hooks';

export const LPDashboard: React.FC = () => {
  const { balance, loading: balanceLoading, refetch: refetchBalance } = useLPBalance();
  const { stats, loading: statsLoading } = usePoolStats();
  const [lpAmount, setLpAmount] = useState('');
  const [removeShares, setRemoveShares] = useState('');

  const handleAddLiquidity = async () => {
    try {
      await addLiquidity(lpAmount);
      refetchBalance();
      setLpAmount('');
    } catch (error) {
      console.error('Failed to add liquidity:', error);
    }
  };

  const handleRemoveLiquidity = async () => {
    try {
      await removeLiquidity(removeShares);
      refetchBalance();
      setRemoveShares('');
    } catch (error) {
      console.error('Failed to remove liquidity:', error);
    }
  };

  if (balanceLoading || statsLoading) return <div>Loading...</div>;

  return (
    <div className="lp-dashboard">
      <h2>Liquidity Provider Dashboard</h2>
      
      <div className="pool-stats">
        <h3>Pool Statistics</h3>
        <div className="stat-item">
          <label>Total Liquidity:</label>
          <span>{stats.totalLiquidity} ETH</span>
        </div>
        <div className="stat-item">
          <label>Total Borrowed:</label>
          <span>{stats.totalBorrowed} ETH</span>
        </div>
        <div className="stat-item">
          <label>Available:</label>
          <span>{stats.available} ETH</span>
        </div>
        <div className="stat-item">
          <label>Utilization:</label>
          <span>{stats.utilization}%</span>
        </div>
      </div>

      <div className="my-position">
        <h3>Your Position</h3>
        <div className="position-item">
          <label>LP Shares:</label>
          <span>{balance.shares}</span>
        </div>
        <div className="position-item">
          <label>ETH Value:</label>
          <span>{balance.value} ETH</span>
        </div>
      </div>

      <div className="lp-actions">
        <div className="add-liquidity">
          <h4>Add Liquidity</h4>
          <input
            type="number"
            placeholder="ETH Amount"
            value={lpAmount}
            onChange={(e) => setLpAmount(e.target.value)}
          />
          <button onClick={handleAddLiquidity}>
            Add Liquidity
          </button>
        </div>

        <div className="remove-liquidity">
          <h4>Remove Liquidity</h4>
          <input
            type="number"
            placeholder="Shares to Remove"
            value={removeShares}
            onChange={(e) => setRemoveShares(e.target.value)}
            max={balance.shares}
          />
          <button onClick={handleRemoveLiquidity}>
            Remove Liquidity
          </button>
        </div>
      </div>
    </div>
  );
};
```

### 5. Error Handling

```typescript
export const getErrorMessage = (error: any): string => {
  const message = error?.message || error?.toString() || '';
  
  if (message.includes('No loans found')) {
    return 'You don\'t have any active loans';
  }
  if (message.includes('No outstanding loan')) {
    return 'No loan found to repay';
  }
  if (message.includes('Insufficient payment')) {
    return 'Please send the exact repayment amount';
  }
  if (message.includes('Insufficient liquidity')) {
    return 'Not enough liquidity available in the pool';
  }
  if (message.includes('user rejected')) {
    return 'Transaction was cancelled';
  }
  
  return 'Transaction failed. Please try again.';
};
```

### 6. Event Listeners

```typescript
export const setupEventListeners = (contract: ethers.Contract, callbacks: {
  onLoanCreated?: (loanId: string, borrower: string, amount: string) => void;
  onLoanRepaid?: (loanId: string, amount: string, interest: string) => void;
  onLiquidityAdded?: (provider: string, amount: string) => void;
  onLiquidityRemoved?: (provider: string, amount: string) => void;
}) => {
  if (callbacks.onLoanCreated) {
    contract.on('LoanCreated', (loanId, borrower, amountETH, preAuthUSD) => {
      callbacks.onLoanCreated?.(
        loanId.toString(),
        borrower,
        ethers.utils.formatEther(amountETH)
      );
    });
  }

  if (callbacks.onLoanRepaid) {
    contract.on('LoanRepaid', (loanId, amountRepaid, interest) => {
      callbacks.onLoanRepaid?.(
        loanId.toString(),
        ethers.utils.formatEther(amountRepaid),
        ethers.utils.formatEther(interest)
      );
    });
  }

  if (callbacks.onLiquidityAdded) {
    contract.on('LiquidityAdded', (provider, amount) => {
      callbacks.onLiquidityAdded?.(
        provider,
        ethers.utils.formatEther(amount)
      );
    });
  }

  if (callbacks.onLiquidityRemoved) {
    contract.on('LiquidityRemoved', (provider, amount) => {
      callbacks.onLiquidityRemoved?.(
        provider,
        ethers.utils.formatEther(amount)
      );
    });
  }
};
```

## Constants

```typescript
export const CREDIT_SHAFT_CONSTANTS = {
  BORROW_APY: 10, // 10% APY
  LTV_RATIO: 50, // 50% Loan-to-Value
  LP_SHARE: 80, // 80% of interest goes to LPs
  PROTOCOL_SHARE: 20, // 20% goes to protocol
  SECONDS_IN_YEAR: 365 * 24 * 60 * 60
};
```

## Deployment Addresses

```typescript
export const ADDRESSES = {
  SEPOLIA: {
    CREDITSHAFT: "0x...", // Your deployed contract address
    ETH_USD_PRICE_FEED: "0x694AA1769357215DE4FAC081bf1f309aDC325306"
  },
  MAINNET: {
    CREDITSHAFT: "0x...", // Your deployed contract address
    ETH_USD_PRICE_FEED: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  }
};
```

## Testing

```typescript
// Example Jest test
describe('CreditShaft Integration', () => {
  it('should check loan status correctly', async () => {
    const { loanInfo } = await useLoanStatus();
    expect(loanInfo).toHaveProperty('hasLoan');
    expect(typeof loanInfo.hasLoan).toBe('boolean');
  });

  it('should format amounts correctly', async () => {
    const amount = ethers.utils.parseEther('1.5');
    const formatted = ethers.utils.formatEther(amount);
    expect(formatted).toBe('1.5');
  });
});
```

## Security Best Practices

1. **Validate Inputs**: Always validate user inputs before sending transactions
2. **Error Handling**: Implement comprehensive error handling
3. **Loading States**: Show loading states during transactions
4. **Gas Estimation**: Estimate gas before transactions
5. **Transaction Monitoring**: Monitor transaction status
6. **Rate Limiting**: Implement rate limiting for API calls
7. **Secure Storage**: Never store private keys in frontend code

## Performance Optimization

1. **Batch Calls**: Use multicall for multiple read operations
2. **Caching**: Cache frequently accessed data
3. **Debouncing**: Debounce user inputs
4. **Lazy Loading**: Load components and data as needed
5. **Memoization**: Use React.memo and useMemo appropriately