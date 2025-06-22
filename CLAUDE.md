# CLAUDE.md

This file provides comprehensive guidance to Claude Code when working with the CreditShaft smart contract repository.

## Project Overview

**CreditShaft** is a next-generation DeFi lending protocol that enables users to borrow ETH using credit card pre-authorizations as collateral. The protocol leverages Chainlink's decentralized infrastructure for secure, real-time payment processing and automated loan management.

### Key Features
- **Credit Card Collateralized Lending**: First-of-its-kind system using Stripe pre-authorizations as DeFi collateral
- **Chainlink Integration**: Functions for Stripe API calls, Automation for loan monitoring, Price Feeds for ETH valuation
- **Interest-Bearing LP Tokens**: AAVE-style liquidity provision with automatic yield accrual via scaled balances
- **Automated Liquidation**: Time-based loan expiry with automatic pre-authorization charging
- **Size-Optimized Contracts**: Minified JavaScript sources embedded in contracts for efficient deployment

## Repository Architecture

```
credit-shaft-contracts/
├── src/                    # Smart contracts
├── script/                 # Deployment scripts
├── javascript/             # Chainlink Functions code
├── test/                   # Test files (currently empty)
├── out/                    # Compiled artifacts
├── broadcast/              # Deployment records
├── lib/                    # Dependencies
├── abi/                    # Extracted ABIs
└── docs/                   # Documentation files
```

### Core Smart Contracts (`src/`)

#### **CreditShaft.sol** - Main Protocol Contract
- **Purpose**: Primary lending protocol with borrowing, repayment, and liquidity management
- **Architecture**: Integrates FunctionsClient, ConfirmedOwner, AutomationCompatibleInterface, and ReentrancyGuard
- **Features**:
  - Multi-loan support per user with detailed loan tracking
  - Chainlink Functions integration for Stripe operations (charge/release)
  - Chainlink Automation for loan expiry monitoring
  - Interest-bearing liquidity pool with dynamic index calculation
  - RAY precision math (1e27) for accurate interest calculations
  - 50% LTV (Loan-to-Value) ratio
  - 10% APY fixed borrowing rate
  - 80/20 interest distribution (80% to LPs, 20% to protocol)

#### **InterestBearingShaftETH.sol** - LP Token Contract
- **Purpose**: ERC20-compliant interest-bearing token using AAVE-style scaled balance system
- **Architecture**: Inherits ERC20 and Ownable, implements WadRayMath library
- **Features**:
  - **Scaled Balances**: User balances stored as shares that grow over time
  - **Dynamic Value**: Real-time balance = shares * liquidityIndex
  - **WAD/RAY Math**: High-precision arithmetic (1e18 WAD, 1e27 RAY)
  - **Index-Based Growth**: Liquidity index tracks cumulative interest accrual
  - **Asset/Share Conversion**: Bidirectional conversion between underlying assets and shares
  - **Transfer Handling**: Custom transfer logic for scaled balances

#### **StripeSources.sol** - Embedded JavaScript Sources
- **Purpose**: Contains minified JavaScript source code for Chainlink Functions
- **Architecture**: Pure functions returning compressed JavaScript strings
- **Features**:
  - **Charge Source**: Captures Stripe Payment Intent when loan expires
  - **Release Source**: Cancels Stripe Payment Intent when loan is repaid
  - **Mock Support**: Handles mock/test Stripe keys for development
  - **Size Optimization**: Heavily minified JavaScript to reduce contract size

### Deployment Scripts (`script/`)

#### **DeployTestEnvironment.s.sol** - Test Deployment
- **Network**: Sepolia testnet
- **Configuration**: Pre-configured with Sepolia Chainlink infrastructure
- **Usage**: `make deploy-sepolia` or `make deploy-sepolia-verify`

#### **DeployCreditShaft.s.sol** - Production Deployment
- **Network**: Mainnet and production testnets
- **Configuration**: Flexible configuration for different networks
- **Usage**: Production deployments with custom parameters

### Chainlink Functions (`javascript/`)

#### **source.js** - Payment Capture Function
- **Purpose**: Captures Stripe pre-authorization when loan expires
- **API**: Stripe Payment Intents API capture endpoint
- **Security**: DON-hosted secrets for API keys

#### **release-source.js** - Pre-authorization Release
- **Purpose**: Cancels Stripe pre-authorization when loan is repaid
- **API**: Stripe Payment Intents cancellation endpoint
- **Integration**: Called automatically on loan repayment

#### **trigger.js** & **release-trigger.js** - Test Scripts
- **Purpose**: Local testing of Chainlink Functions
- **Usage**: `npm run trigger` and `npm run release-trigger`

#### **request.js** - Utility Script
- **Purpose**: General request testing and debugging

## Development Environment

### Prerequisites
```bash
# Required tools
curl -L https://foundry.paradigm.xyz | bash  # Foundry
foundryup                                    # Latest Foundry
node --version                              # Node.js 16+
git submodule update --init --recursive     # Git submodules
```

### Installation & Setup
```bash
# Clone and setup
git clone <repository>
cd credit-shaft-contracts

# Install dependencies
forge install
npm install

# Setup environment
make setup                    # Creates .env from template
```

### Environment Configuration

#### Required Environment Variables
```bash
# Network Configuration
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY

# Deployment Configuration
DEPLOYER_ACCOUNT=default                    # Foundry account name
DEPLOYER_ADDRESS=0x1234...                  # Deployer wallet address
ETHERSCAN_API_KEY=ABC123...                # For contract verification

# Chainlink Configuration
DON_HOSTED_SECRETS_VERSION=1234567890      # Chainlink secrets version
```

#### Network-Specific Configuration
```bash
# Sepolia Testnet (Pre-configured)
SEPOLIA_ROUTER=0xb83E47C2bC239B3bf370bc41e1459A34b41238D0
SEPOLIA_DON_ID=fun-ethereum-sepolia-1
ETH_USD_FEED_SEPOLIA=0x694AA1769357215DE4FAC081bf1f309aDC325306

# Local Development
ANVIL_RPC=http://localhost:8545
ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## Build & Testing Commands

### Primary Build Commands
```bash
# Core building
forge build                          # Compile all contracts
forge clean                          # Clean build artifacts
forge fmt                            # Format Solidity code

# Advanced building
forge build --sizes                  # Show contract sizes
forge build --gas-report            # Generate gas report
```

### Testing Commands
```bash
# Smart contract testing
forge test                           # Run all tests
forge test -vvv                      # Verbose output
forge test --gas-report             # With gas usage

# JavaScript testing
npm run trigger                      # Test payment capture
npm run release-trigger              # Test pre-auth release
npm run request                      # General testing
```

### Quality Assurance
```bash
# Code quality
make fmt                             # Format all code
make lint                            # Run Solhint (if available)
make gas-snapshot                    # Create gas baseline

# Environment validation
make check-env                       # Verify .env configuration
```

## Deployment Workflows

### Local Development Deployment
```bash
# Terminal 1: Start local node
make anvil

# Terminal 2: Deploy to local
make deploy-local
```

### Testnet Deployment (Sepolia)
```bash
# Quick deployment
make deploy-sepolia

# With contract verification
make deploy-sepolia-verify

# Manual verification (if needed)
make verify-sepolia
```

### Production Deployment Process
```bash
# 1. Environment setup
make check-env                       # Verify configuration

# 2. Deploy contracts
forge script script/DeployCreditShaft.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --account $DEPLOYER_ACCOUNT \
  --sender $DEPLOYER_ADDRESS \
  --broadcast \
  --verify

# 3. Post-deployment setup
# - Fund contract with LINK tokens
# - Register with Chainlink Functions
# - Setup Automation upkeep
# - Upload DON secrets
```

## Smart Contract Details

### CreditShaft Contract Architecture

#### Core Functions
```solidity
// Borrowing - Creates new loan with Stripe pre-auth
function borrowETH(uint256 preAuthAmountUSD, uint256 preAuthDurationMinutes, 
                   string memory stripePaymentIntentId, string memory stripeCustomerId, 
                   string memory stripePaymentMethodId) external returns (uint256 loanId)

// Repayment - Repays loan and releases pre-auth
function repayLoan(uint256 loanId) external payable

// Liquidity provision - Updates index before minting/burning
function addLiquidity() external payable
function removeLiquidity(uint256 shares) external
```

#### Data Retrieval Functions
```solidity
// User data
function getUserLoans(address user) external view returns (uint256[] memory)
function getActiveLoansForUser(address user) external view returns (uint256[] memory, uint256)
function hasActiveLoan(address user) external view returns (bool)

// Loan details with calculated interest
function getLoanDetails(uint256 loanId) external view returns (
    address borrower, uint256 borrowedETH, uint256 preAuthAmountUSD,
    uint256 currentInterest, uint256 totalRepayAmount, uint256 createdAt,
    uint256 preAuthExpiry, bool isActive, bool isExpired
)

// Repayment calculation with buffer
function getRepayAmount(uint256 loanId) external view returns (uint256)

// Pool statistics
function getPoolStats() external view returns (uint256, uint256, uint256, uint256)
function getUserLPBalance(address user) external view returns (uint256, uint256)
```

#### Administrative Functions
```solidity
// Chainlink Functions management
function chargePreAuth(uint256 loanId) external onlyOwner
function releasePreAuth(uint256 loanId) external onlyOwner
function updateDONHostedSecretsVersion(uint64 version) external onlyOwner

// Protocol management
function withdrawProtocolFees() external onlyOwner
function getLiquidityIndex() external view returns (uint256)
```

### InterestBearingShaftETH Token Features

#### Scaled Balance System
- **Shares Storage**: User balances stored as shares (scaled amounts)
- **Real-time Value**: `balanceOf(user) = shares[user] * liquidityIndex`
- **Index Growth**: Liquidity index increases over time based on protocol interest
- **Precision**: RAY precision (1e27) for high-accuracy calculations

#### Core Functions
```solidity
// Asset/Share conversion (view functions)
function convertToShares(uint256 assets) external view returns (uint256)
function convertToAssets(uint256 shares) external view returns (uint256)

// Balance queries
function balanceOf(address account) external view returns (uint256)  // Real-time balance
function scaledBalanceOf(address user) external view returns (uint256)  // Shares
function totalSupply() external view returns (uint256)  // Real-time total
function scaledTotalSupply() external view returns (uint256)  // Total shares

// Administrative (owner-only)
function mint(address to, uint256 shares) external onlyOwner
function burn(address from, uint256 shares) external onlyOwner
```

#### Transfer Mechanics
- **Amount Parameter**: Transfer functions accept asset amounts (not shares)
- **Internal Conversion**: Asset amounts converted to shares for internal tracking
- **Event Emission**: Standard ERC20 events emitted with asset amounts

### Interest Rate Calculation

#### Liquidity Index Formula
```solidity
// Utilization-based interest accrual
utilization = totalBorrowed / totalLiquidity
lpRate = (BORROW_APY * utilization * LP_SHARE) / (100 * 1e18 * 100)
newIndex = liquidityIndex * (1e27 + (lpRate * timeElapsed) / (365 days)) / 1e27
```

#### Interest Distribution
- **Borrower Rate**: 10% APY fixed
- **LP Share**: 80% of interest goes to liquidity providers
- **Protocol Share**: 20% of interest goes to protocol treasury
- **Calculation**: Real-time interest based on time elapsed since loan creation

### Chainlink Integration Points

#### Functions Integration
- **Payment Capture**: Charges expired pre-authorizations via Stripe API
- **Payment Release**: Cancels pre-authorizations on repayment
- **Error Handling**: Robust error management with cleanup on failures
- **Security**: DON-hosted secrets for API credentials
- **Request Tracking**: Maps Chainlink request IDs to loan IDs

#### Automation Integration
- **Monitoring**: `checkUpkeep` scans for expired loans
- **Triggering**: `performUpkeep` automatically charges expired pre-auths
- **Gas Optimization**: Single loan processing per upkeep call

#### Price Feed Integration
- **ETH/USD**: Real-time price data for loan calculations
- **LTV Calculation**: 50% loan-to-value ratio enforcement
- **Oracle Security**: Chainlink's proven price feed infrastructure

## Security Considerations

### Smart Contract Security
```solidity
// Applied security measures
ReentrancyGuard           // Prevents reentrancy attacks on state-changing functions
ConfirmedOwner           // Secure two-step ownership management
Event logging            // Complete audit trail for all operations
Input validation         // All functions validate inputs and state
RAY precision math       // Prevents calculation errors and overflow
Loan state checks        // Prevents double-spending and invalid operations
```

### Chainlink Security
- **DON Secrets**: Encrypted secret management for Stripe API keys
- **Request Validation**: All requests include validation and error handling
- **Mapping Cleanup**: Proper cleanup of request mappings on completion/failure
- **Access Control**: Owner-only administrative functions

### Operational Security
- **Multi-sig recommended**: For production ownership
- **Time delays**: Consider implementing time locks for sensitive operations
- **Monitoring**: Event-based monitoring for unusual activity
- **Upgradability**: Consider proxy patterns for future updates

## Testing Strategy

### Current Testing Status
- **Unit Tests**: Not yet implemented (test/ directory exists but empty)
- **Integration Tests**: Available via npm scripts for Chainlink Functions
- **Manual Testing**: Deployment scripts provide manual testing capability

### Recommended Testing Implementation
```bash
# Unit tests to implement
test/CreditShaft.t.sol              # Core lending logic
test/InterestBearingShaftETH.t.sol  # LP token functionality
test/StripeSources.t.sol            # JavaScript source validation
test/ChainlinkIntegration.t.sol     # Functions and Automation

# Integration tests
test/integration/                   # End-to-end workflow tests
test/fuzzing/                      # Foundry fuzz testing
test/invariant/                    # Invariant testing
```

### Testing Best Practices
```solidity
// Test structure
contract CreditShaftTest is Test {
    CreditShaft creditShaft;
    InterestBearingShaftETH lpToken;
    
    function setUp() public {
        // Deploy contracts with proper constructor parameters
        // Setup test state with mock Chainlink infrastructure
    }
    
    function testBorrowingWorkflow() public {
        // Test complete borrowing flow with pre-auth
    }
    
    function testInterestAccrual() public {
        // Test liquidity index updates and interest calculations
    }
    
    function testScaledBalances() public {
        // Test LP token scaled balance mechanics
    }
}
```

## Development Workflows

### Feature Development Process
1. **Design**: Plan contract changes and impacts
2. **Implementation**: Write/modify Solidity code
3. **Testing**: Local testing with `make deploy-local`
4. **Formatting**: Run `make fmt` for code formatting
5. **Integration**: Test with Chainlink Functions if applicable
6. **Deployment**: Deploy to Sepolia with `make deploy-sepolia-verify`
7. **Verification**: Ensure contract verification succeeds

### Code Modification Guidelines
```bash
# Before making changes
forge build                     # Ensure clean build
forge test                      # Run existing tests

# After making changes
forge build                     # Check compilation
forge fmt                       # Format code
make deploy-local               # Test locally
make deploy-sepolia             # Test on testnet
```

### Contract Size Management
```bash
# Monitor contract sizes
forge build --sizes

# If approaching 24KB limit:
# 1. Further minify JavaScript strings in StripeSources.sol
# 2. Extract duplicate code to libraries
# 3. Optimize function signatures
# 4. Consider splitting into multiple contracts
```

## Troubleshooting Guide

### Common Build Issues
```bash
# Issue: Compilation fails
forge clean && forge build

# Issue: Missing dependencies
forge install

# Issue: Outdated Foundry
foundryup

# Issue: Node.js dependencies
npm install
```

### Deployment Issues
```bash
# Issue: Insufficient gas
# Solution: Increase gas limit in deployment script

# Issue: Contract verification fails
# Solution: Check constructor arguments match deployment

# Issue: Environment variables not loaded
# Solution: Ensure .env file exists and is properly formatted
```

### Chainlink Integration Issues
```bash
# Issue: Functions requests fail
# Solution: Check DON secrets are uploaded and version is correct

# Issue: Automation not triggering
# Solution: Verify upkeep registration and funding

# Issue: Price feed data stale
# Solution: Check price feed address and network compatibility
```

### Interest Calculation Issues
```bash
# Issue: LP balances not updating
# Solution: Ensure liquidity index is being updated in addLiquidity/removeLiquidity

# Issue: Scaled balance errors
# Solution: Check RAY precision calculations and conversions
```

## Contract Interfaces & ABIs

### Core Interface Definitions
```solidity
interface IInterestBearingShaftETH {
    function mint(address to, uint256 shares) external;
    function burn(address from, uint256 shares) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
}

interface ICreditShaftForLP {
    function totalLiquidity() external view returns (uint256);
    function getLiquidityIndex() external view returns (uint256);
}
```

### ABI Extraction
```bash
# Extract ABIs after compilation
mkdir -p abi
jq '.abi' out/CreditShaft.sol/CreditShaft.json > abi/CreditShaft.json
jq '.abi' out/InterestBearingShaftETH.sol/InterestBearingShaftETH.json > abi/InterestBearingShaftETH.json
jq '.abi' out/StripeSources.sol/StripeSources.json > abi/StripeSources.json
```

## Frontend Integration

### Contract Addresses
- **Artifacts Location**: `out/` directory after compilation
- **Deployment Records**: `broadcast/` directory with transaction details
- **Network Configuration**: Sepolia testnet ready, mainnet requires deployment

### Key Integration Points
```typescript
// Frontend integration example
const creditShaft = new ethers.Contract(address, abi, signer);
const lpToken = new ethers.Contract(lpTokenAddress, lpTokenAbi, signer);

// Get user's loans
const userLoans = await creditShaft.getUserLoans(userAddress);

// Get loan details with calculated interest
const loanDetails = await creditShaft.getLoanDetails(loanId);

// Get real-time LP balance (not scaled)
const lpBalance = await lpToken.balanceOf(userAddress);

// Get scaled LP balance (shares)
const scaledBalance = await lpToken.scaledBalanceOf(userAddress);

// Repay loan with buffer
const repayAmount = await creditShaft.getRepayAmount(loanId);
await creditShaft.repayLoan(loanId, { value: repayAmount });
```

## Monitoring & Operations

### Event Monitoring
```solidity
// Key events to monitor
event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 amountETH, uint256 preAuthUSD);
event LoanRepaid(uint256 indexed loanId, uint256 amountRepaid, uint256 interest);
event PreAuthCharged(uint256 indexed loanId, string paymentIntentId);
event PreAuthReleased(uint256 indexed loanId, string paymentIntentId);
event LiquidityAdded(address indexed provider, uint256 amount);
event LiquidityRemoved(address indexed provider, uint256 amount);
event RewardsDistributed(uint256 toLPs, uint256 toProtocol);

// LP Token events
event Mint(address indexed user, uint256 shares, uint256 index);
event Burn(address indexed user, uint256 shares, uint256 index);
event BalanceTransfer(address indexed from, address indexed to, uint256 assetAmount, uint256 index);
```

### Operational Monitoring
- **Loan Expiry**: Monitor upcoming loan expirations via checkUpkeep
- **Liquidity Levels**: Track pool utilization and available liquidity
- **Interest Rates**: Monitor dynamic liquidity index changes
- **Chainlink Health**: Verify Functions and Automation are operational
- **Scaled Balances**: Monitor LP token share/asset ratio accuracy

## Version Information & Dependencies

### Solidity Environment
- **Solidity Version**: ^0.8.19 (specified in foundry.toml)
- **Foundry**: Latest stable version
- **EVM Target**: Paris (default)

### Dependencies
```toml
# Foundry dependencies (lib/)
forge-std = { git = "https://github.com/foundry-rs/forge-std" }
foundry-chainlink-toolkit = { git = "https://github.com/smartcontractkit/foundry-chainlink-toolkit" }
openzeppelin-contracts = { git = "https://github.com/OpenZeppelin/openzeppelin-contracts" }
```

### Node.js Dependencies
```json
{
  "@chainlink/functions-toolkit": "^0.3.2",
  "@chainlink/env-enc": "^1.0.5",
  "ethers": "^5.7.2"
}
```

## Support & Documentation

### Additional Resources
- **INTEGRATION.md**: Frontend integration guide
- **CHANGES.md**: Breaking changes and migration guide
- **README.md**: Quick start guide

### Getting Help
- Check existing documentation files
- Review deployment logs in `broadcast/` directory
- Test locally with `make deploy-local`
- Use verbose deployment flags (`-vvv`) for debugging

## Support & Documentation

### Additional Resources
- **INTEGRATION.md**: Frontend integration guide
- **CHANGES.md**: Breaking changes and migration guide
- **README.md**: Quick start guide

### Getting Help
- Check existing documentation files
- Review deployment logs in `broadcast/` directory
- Test locally with `make deploy-local`
- Use verbose deployment flags (`-vvv`) for debugging