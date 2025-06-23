# CLAUDE.md

## Project Overview

CreditShaft is a hackathon DeFi project that enables leveraged trading with Stripe payment card collateral. Users can open 2x-5x LINK positions while having their credit card pre-authorized as backup collateral.

## Core Contracts

- **CreditShaftCore.sol**: USDC flash loan provider
- **CreditShaftLeverage.sol**: Main leverage trading contract
- **AaveStrategy.sol**: Aave V3 integration wrapper
- **SimplifiedLPToken.sol**: LP tokens for liquidity providers

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
1. Add USDC liquidity to CreditShaftCore
2. Add contract to Chainlink Functions subscription
3. Fund with LINK tokens

## Key Addresses (Sepolia)

- USDC: `0xa0B86a33e6441C8FaFA04F8Cb0b99bb4C6659d31`
- LINK: `0x779877A7B0D9E8603169DdbD7836e478b4624789`
- Aave Pool: `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951`
- Uniswap Router: `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008`

## Integration

### Frontend Integration
After deployment, use the contract addresses logged to interact with:
- `openLeveragePosition()` - Create leveraged position
- `closeLeveragePosition()` - Close position
- `addUSDCLiquidity()` - Provide flash loan liquidity

### Stripe Integration
Pre-auth flow handled via Chainlink Functions calling Stripe API with stored payment intents.