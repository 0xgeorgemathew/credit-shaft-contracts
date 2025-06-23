# CreditShaft Makefile - Hackathon Edition

.PHONY: build test clean fmt deploy-sepolia

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
	forge script script/DeployCreditShaftLeverage.s.sol:DeployCreditShaftLeverage \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(DEPLOYER_ACCOUNT) \
		--sender $(DEPLOYER_ADDRESS) \
		--broadcast \
		--verify

# Local development
anvil:
	anvil

# Gas snapshot
gas-snapshot:
	forge snapshot