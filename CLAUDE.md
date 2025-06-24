# CLAUDE.md

## Project Overview

CreditShaft is a hackathon DeFi project that enables leveraged trading with Stripe payment card collateral. Users can open 2x-5x LINK positions while having their credit card pre-authorized as backup collateral.

## Core Contracts

- **CreditShaftCore.sol**: USDC flash loan provider with LP system for liquidity providers
- **CreditShaftLeverage.sol**: Main leverage trading contract
- **AaveStrategy.sol**: Aave V3 integration wrapper
- **SimplifiedLPToken.sol**: LP tokens deployed by CreditShaftCore

## Architecture

- **Flash Loan System**: CreditShaftCore provides USDC flash loans to CreditShaftLeverage
- **LP Rewards**: Flash loan LPs earn fees from flash loans + 20% of leverage trading profits
- **Reward Flow**: Leverage profits → CreditShaftCore → Distributed to LP token holders

## Quick Demo Flow

1. **Open Position**: User deposits 1 LINK + provides Stripe payment details → Gets 2x LINK exposure
2. **Close Position**: User closes → Gets profit/loss + pre-auth released
3. **Timeout**: If position open too long → Card gets charged automatically

## Development Commands

```bash
# Build
forge build

# Test
forge test

# Deploy to Sepolia
make deploy-sepolia

# Format code
forge fmt
```

## Testnet Deployment

### Required Setup
```bash
# .env file
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
DEPLOYER_ACCOUNT=deployerKey
DEPLOYER_ADDRESS=0x20e5b952942417d4cb99d64a9e06e41dcef00000
ETHERSCAN_API_KEY=your_key
DON_HOSTED_SECRETS_VERSION=1750465781
```

### Setup Foundry Account
```bash
# Import your private key to Foundry keystore
cast wallet import deployerKey --interactive
```

### Deploy Command
```bash
make deploy-sepolia
```

### Post-Deploy
1. Add USDC liquidity to CreditShaftCore (call `addUSDCLiquidity()` to become flash loan LP)
2. Add CreditShaftLeverage contract to Chainlink Functions subscription
3. Fund Chainlink subscription with LINK tokens

## Key Addresses (Sepolia)

- USDC: `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`
- LINK: `0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5`
- Aave Pool: `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951`
- Uniswap Router: `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008`
- LINK Price Feed: `0xc59E3633BAAC79493d908e63626716e204A45EdF`
- Functions Router: `0xb83E47C2bC239B3bf370bc41e1459A34b41238D0`

## Integration

### Frontend Integration
After deployment, use the contract addresses logged to interact with:
- `openLeveragePosition()` - Create leveraged position (on CreditShaftLeverage)
- `closeLeveragePosition()` - Close position (on CreditShaftLeverage)
- `addUSDCLiquidity()` - Become flash loan LP and earn rewards (on CreditShaftCore)
- `removeUSDCLiquidity()` - Withdraw LP tokens + accumulated rewards (on CreditShaftCore)

### Stripe Integration
Pre-auth flow handled via Chainlink Functions calling Stripe API with stored payment intents.