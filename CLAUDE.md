# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CreditShaft is a revolutionary DeFi credit lending protocol that allows users to borrow cryptocurrency using credit cards as collateral. The platform leverages Chainlink Automation and Chainlink Functions to create a trustless, automated liquidation system that directly interfaces with Stripe's API.

## Development Commands

### Build and Testing
- `forge build` - Compile smart contracts
- `forge test` - Run test suite
- `forge test -vvv` - Run tests with verbose output
- `forge fmt` - Format Solidity code
- `forge snapshot` - Generate gas usage snapshots

### Local Development
- `anvil` - Start local Ethereum node
- `forge script script/DeployCreditShaft.s.sol:DeployCreditShaft --rpc-url <rpc_url> --private-key <private_key>` - Deploy CreditShaft contracts
- `forge script script/DeployTestEnvironment.s.sol:DeployTestEnvironment --rpc-url <rpc_url> --private-key <private_key>` - Deploy with test configuration

### Network Configuration
- Sepolia RPC configured in foundry.toml: `https://eth-sepolia.g.alchemy.com/v2/5NIZupGMAK990bNPC95clhTZBkvw4BrE`

## Architecture Overview

### Core Contracts
- **InterestBearingCBLP.sol** - AAVE-style interest-bearing LP token with real-time balance growth using ray math precision
- **CreditShaft.sol** - Main protocol contract integrating Chainlink Functions and Automation with Stripe API for automated liquidation and pre-authorization release

### Key Integrations
- **Chainlink Functions** - Direct HTTP requests to Stripe API for payment capture
- **Chainlink Automation** - Time-based monitoring of loan expiry and automated liquidation triggers
- **OpenZeppelin** - Standard implementations for ERC20, access control, and security patterns

### Chainlink Components
- Functions Router: `0xb83E47C2bC239B3bf370bc41e1459A34b41238D0` (Sepolia)
- DON ID: `fun-ethereum-sepolia-1`
- Automation monitoring for pre-authorization expiry
- Secrets management for Stripe API keys in Chainlink DON

## Smart Contract Structure

### CreditShaft Contract
- Manages ETH lending against credit card pre-authorizations
- Integrates Chainlink Automation for expiry monitoring via `checkUpkeep()` and `performUpkeep()`
- Uses Chainlink Functions for Stripe API calls in `_chargePreAuth()` and `_releasePreAuth()`
- Implements AAVE-style liquidity pool with interest-bearing LP tokens
- Handles automated liquidation and pre-authorization release through `fulfillRequest()` callback
- Automatic pre-auth release on loan repayment for better UX
- Real-time interest accrual using liquidity index with RAY precision

### State Management
- On-chain: Loan terms, automation triggers, liquidation status
- Off-chain: Sensitive payment data, user analytics, API logs
- Events emitted for all state changes to enable monitoring

## Dependencies and Libraries

### Foundry Libraries
- `forge-std` - Testing and scripting utilities
- `foundry-chainlink-toolkit` - Chainlink contract integrations
- `openzeppelin-contracts` - Standard contract implementations

### Import Remappings
- `@chainlink/contracts/` → `lib/chainlink-brownie-contracts/contracts/src/`
- `@openzeppelin/` → `lib/openzeppelin-contracts/`
- `forge-std/` → `lib/forge-std/src/`

## Development Notes

### Testing Strategy
- Unit tests in `test/` directory follow Foundry conventions
- Use `forge test` for local testing
- Gas optimization verified through `forge snapshot`
- Integration testing requires Chainlink testnet setup

### Deployment Considerations
- Requires Chainlink Functions subscription and LINK funding
- Stripe API keys must be uploaded to Chainlink DON secrets
- Automation upkeep registration needed for loan monitoring
- Contract must be added as consumer to Functions subscription

### Security Features
- ReentrancyGuard on all financial functions
- Access control via OpenZeppelin Ownable
- Pre-authorization expiry monitoring prevents indefinite holds
- Automatic pre-auth release on loan repayment prevents unnecessary card holds
- Ray math precision prevents interest calculation errors
- Scaled balance system prevents precision loss in transfers
- Event emission for transparency and monitoring

## Contract Interfaces and Features

### InterestBearingCBLP Features
- **Real-time Balance Growth**: Balances increase automatically as interest accrues (AAVE-style)
- **Ray Math Precision**: Uses 1e27 precision for accurate interest calculations
- **Scaled Balances**: Internal scaled balance tracking prevents precision loss
- **Liquidity Index**: Dynamic index that grows with pool utilization and time
- **Transfer Support**: Full ERC20 compatibility with scaled balance transfers

### CreditShaft Core Functions
- `borrowETH()` - Create loan with credit card pre-authorization
- `repayLoan()` - Repay loan with automatic pre-auth release
- `addLiquidity()` - Provide ETH liquidity and receive interest-bearing tokens
- `removeLiquidity()` - Withdraw liquidity using shares
- `chargePreAuth()` - Manual pre-authorization charge (owner only)
- `releasePreAuth()` - Manual pre-authorization release (owner only)
- `getLiquidityIndex()` - Get current liquidity index for interest calculations

### JavaScript Integration Files
- `javascript/source.js` - Chainlink Function for Stripe payment capture
- `javascript/release-source.js` - Chainlink Function for Stripe pre-auth cancellation
- `javascript/trigger.js` - Test script for payment capture functionality
- `javascript/release-trigger.js` - Test script for pre-auth release functionality

### Deployment Scripts
- `script/DeployCreditShaft.s.sol` - Production deployment script
- `script/DeployTestEnvironment.s.sol` - Test environment with default settings

## Example Implementations
- `@src/FunctionsConsumerExample.sol` - Example implementation for testing
- `@abi/functionsClient.json` - ABI for Functions consumer contract