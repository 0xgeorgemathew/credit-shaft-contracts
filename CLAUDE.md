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
- `forge script script/Counter.s.sol:CounterScript --rpc-url <rpc_url> --private-key <private_key>` - Deploy contracts

### Network Configuration
- Sepolia RPC configured in foundry.toml: `https://eth-sepolia.g.alchemy.com/v2/5NIZupGMAK990bNPC95clhTZBkvw4BrE`

## Architecture Overview

### Core Contracts
- **CBLP.sol** - ERC20 LP token for liquidity providers in the credit bridge system
- **CreditBridge.sol** - Main protocol contract integrating Chainlink Functions and Automation with Stripe API for automated liquidation

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

### CreditBridge Contract
- Manages ETH lending against credit card pre-authorizations
- Integrates Chainlink Automation for expiry monitoring via `checkUpkeep()` and `performUpkeep()`
- Uses Chainlink Functions for direct Stripe API calls in `_chargePreAuth()`
- Implements liquidity pool mechanics with LP token rewards
- Handles automated liquidation through `fulfillRequest()` callback

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
- Event emission for transparency and monitoring

## Example Implementations
- `@src/FunctionsConsumerExample.sol` Is an Example Implementation Deployed for test purposes
- `@abi/functionsClient.json` Is its ABI