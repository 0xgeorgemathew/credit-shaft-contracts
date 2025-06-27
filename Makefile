# CreditShaft Makefile - Hackathon Edition
# Load environment variables
include .env
export
.PHONY: build test clean fmt deploy-sepolia setup-test-liquidity mint-usdc-liquidity mint-link mint-usdc test-open-position

# Basic commands
build:
	forge build

test:
	forge test

clean:
	forge clean

fmt:
	forge fmt

# Deployment
deploy-sepolia:
	@echo "Deploying to Sepolia..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	forge script script/DeployCreditShaftLeverage.s.sol:DeployCreditShaftLeverage \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast \
		--verify \
		--delay 30 \
		--retries 20 

# Setup test liquidity after deployment
setup-test-liquidity:
	@echo "Setting up test liquidity..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	@if [ -z "$(CREDIT_SHAFT_CORE)" ]; then echo "Error: CREDIT_SHAFT_CORE not set"; exit 1; fi
	CREDIT_SHAFT_CORE=$(CREDIT_SHAFT_CORE) forge script script/SetupTestLiquidity.s.sol:SetupTestLiquidity \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast \


# Mint USDC and add to CreditShaft
mint-usdc-liquidity:
	@echo "Minting 100K USDC and adding to CreditShaft..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	@if [ -z "$(CREDIT_SHAFT_CORE)" ]; then echo "Error: CREDIT_SHAFT_CORE not set"; exit 1; fi
	CREDIT_SHAFT_CORE=$(CREDIT_SHAFT_CORE) forge script script/MintUSDCLiquidity.s.sol:MintUSDCLiquidity \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast

# Local development
anvil:
	anvil

# Gas snapshot
gas-snapshot:
	forge snapshot

# Mint LINK tokens
mint-link:
	@echo "Minting 100K LINK tokens..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	forge script script/MintLinkiquidity.s.sol:MintLinkLiquidity \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast

# Mint USDC tokens
mint-usdc:
	@echo "Minting 100K USDC tokens..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	forge script script/MintUSDC.s.sol:MintUSDC \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast

# Test leverage position opening
test-open-position:
	@echo "Testing openLeveragePosition() call..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "Error: SEPOLIA_RPC_URL not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ACCOUNT)" ]; then echo "Error: DEPLOYER_ACCOUNT not set"; exit 1; fi
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "Error: DEPLOYER_ADDRESS not set"; exit 1; fi
	forge script script/OpenPosition.s.sol:OpenPosition \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast
test-close-position:
	@echo "Testing closeLeveragePosition() call..."
	@forge script script/ClosePosition.s.sol:ClosePosition \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast -vvv
repay-aave-debt:
	@echo "Testing repayAaveDebt() call..."
	@forge script script/RepayAaveDebt.s.sol:RepayAaveDebt \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast -vvv
find-and-repay:
	@echo "🤖 Launching Auto-Repayment Bot..."
	@forge script script/FindAndRepayDebt.s.sol:FindAndRepayDebt \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--ffi \
		-vvvv
stats:
	@forge script script/CreditShaftStats.s.sol \
 	--rpc-url $(SEPOLIA_RPC_URL)