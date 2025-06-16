# Load environment variables
include .env
export

# Default target
.DEFAULT_GOAL := help

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

## Help
help: ## Show this help message
	@echo "$(GREEN)CreditShaft Deployment Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(YELLOW)<target>$(NC)\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

## Build
build: ## Compile contracts
	@echo "$(GREEN)Building contracts...$(NC)"
	forge build

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	forge clean


## Deployment
deploy-sepolia: ## Deploy to Sepolia testnet
	@echo "$(GREEN)Deploying to Sepolia...$(NC)"
	forge script script/DeployTestEnvironment.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast \
		-vvvv

deploy-sepolia-verify: ## Deploy to Sepolia and verify contracts
	@echo "$(GREEN)Deploying to Sepolia with verification...$(NC)"
	forge script script/DeployTestEnvironment.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv



## Verification
verify-sepolia: ## Verify already deployed contract on Sepolia
	@echo "$(GREEN)Verifying contract on Sepolia...$(NC)"
	@read -p "Enter contract address: " address; \
	forge verify-contract $$address \
		src/CreditShaft.sol:CreditShaft \
		--chain-id 11155111 \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--constructor-args $$(cast abi-encode "constructor(address,uint64,bytes32)" $(SEPOLIA_ROUTER) $(TEST_SUBSCRIPTION_ID) $(SEPOLIA_DON_ID))

## Local Development
anvil: ## Start local Anvil node
	@echo "$(GREEN)Starting Anvil local node...$(NC)"
	anvil --host 0.0.0.0 --port 8545

deploy-local: ## Deploy to local Anvil node
	@echo "$(GREEN)Deploying to local Anvil...$(NC)"
	forge script script/DeployTestEnvironment.s.sol \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast \
		-vvvv

## Utilities
fmt: ## Format code
	@echo "$(GREEN)Formatting code...$(NC)"
	forge fmt

lint: ## Run linter (requires solhint)
	@echo "$(GREEN)Running linter...$(NC)"
	solhint 'src/**/*.sol' 'test/**/*.sol' 'script/**/*.sol'

gas-snapshot: ## Create gas usage snapshot
	@echo "$(GREEN)Creating gas snapshot...$(NC)"
	forge snapshot

check-env: ## Check if .env file exists and has required variables
	@echo "$(GREEN)Checking environment configuration...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(RED)Error: .env file not found. Copy .env.example to .env and configure.$(NC)"; \
		exit 1; \
	fi
	@echo "✓ .env file exists"
	@echo "✓ SEPOLIA_RPC_URL: $(SEPOLIA_RPC_URL)"
	@echo "✓ DEPLOYER_ACCOUNT: $(DEPLOYER_ACCOUNT)"
	@echo "✓ DEPLOYER_ADDRESS: $(DEPLOYER_ADDRESS)"

setup: ## Initial project setup
	@echo "$(GREEN)Setting up project...$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(YELLOW)Created .env file from .env.example. Please configure your settings.$(NC)"; \
	fi
	forge install
	@echo "$(GREEN)Setup complete!$(NC)"

## Contract Interaction (add your contract interaction commands here)
# Example: call a view function
# call-total-supply: ## Get total LP token supply
# 	@read -p "Enter contract address: " address; \
# 	cast call $$address "totalSupply()(uint256)" --rpc-url $(SEPOLIA_RPC_URL)

.PHONY: help build clean test test-gas coverage deploy-sepolia deploy-sepolia-verify deploy-mainnet verify-sepolia anvil deploy-local fmt lint gas-snapshot check-env setup