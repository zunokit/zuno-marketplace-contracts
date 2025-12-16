.PHONY: help build test clean anvil anvil-clean deploy-all-local format snapshot coverage

LOCAL_RPC := http://localhost:8545

help:
	@echo "Zuno Marketplace Contracts - Makefile Commands"
	@echo ""
	@echo "Build & Test:"
	@echo "  make build              - Build all contracts"
	@echo "  make test               - Run all tests"
	@echo "  make test-v             - Run tests with verbose output"
	@echo "  make test-vvv           - Run tests with maximum verbosity"
	@echo "  make coverage           - Generate test coverage report"
	@echo "  make snapshot           - Generate gas snapshots"
	@echo "  make format             - Format Solidity code"
	@echo "  make clean              - Clean build artifacts"
	@echo ""
	@echo "Local Development:"
	@echo "  make anvil              - Start Anvil with persistent state (port 8545)"
	@echo "  make anvil-clean        - Start Anvil with fresh state (no persistence)"
	@echo "  make deploy-all-local   - Deploy all contracts to local network"
	@echo ""

# Build contracts
build:
	forge build

# Run tests
test:
	forge test

test-v:
	forge test -vv

test-vvv:
	forge test -vvv

# Test specific file
test-file:
	@echo "Usage: make test-file FILE=test/unit/YourTest.t.sol"
	forge test --match-path $(FILE) -vvv

# Test specific pattern
test-match:
	@echo "Usage: make test-match PATTERN=testFunctionName"
	forge test --match-test $(PATTERN) -vvv

# Coverage
coverage:
	forge coverage

# Gas snapshots
snapshot:
	forge snapshot

# Format code
format:
	forge fmt

# Clean artifacts
clean:
	forge clean

# Start local Anvil blockchain with persistent state
anvil:
	@echo Starting Anvil with persistent state...
	@if exist state.json (anvil --port 8545 --load-state state.json --dump-state state.json) else (anvil --port 8545 --dump-state state.json)

# Start Anvil with fresh state (no persistence)
anvil-clean:
	@if exist state.json del state.json
	anvil --port 8545

# Deploy all contracts to local network
deploy-all-local:
	forge script script/deploy/DeployAll.s.sol:DeployAll --rpc-url $(LOCAL_RPC) --broadcast --force

# Install dependencies
install:
	forge install

# Update dependencies
update:
	forge update
