# Deployment Guide

## Prerequisites

- Foundry installed and configured
- RPC endpoints configured in `foundry.toml`
- Private keys secured in `.env` or hardware wallet
- Sufficient ETH for deployment gas

## Pre-deployment Checklist

- [ ] All tests passing (`forge test`)
- [ ] Security audit completed
- [ ] Contract parameters configured
- [ ] Multisig wallet setup
- [ ] Monitoring infrastructure ready

## Step-by-Step Deployment

### 1. Local Testing

```bash
# Start local chain
make start-anvil

# Deploy to local
make deploy-all-local

# Verify deployment
forge test --fork-url http://localhost:8545
```

### 2. Testnet Deployment (Sepolia)

```bash
# Set environment variables
export SEPOLIA_RPC_URL="https://..."
export PRIVATE_KEY="0x..."
export MARKETPLACE_WALLET="0x..."

# Deploy ALL contracts with single script
forge script script/deploy/DeployAll.s.sol \\
  --rpc-url $SEPOLIA_RPC_URL \\
  --broadcast \\
  --verify

# Output will provide UserHub and AdminHub addresses
# Frontend needs UserHub, Admin needs AdminHub
```

### 3. Mainnet Deployment

⚠️ **CRITICAL**: Use hardware wallet and multisig

```bash
# Additional mainnet checks
- [ ] Audit report reviewed
- [ ] Parameters double-checked
- [ ] Multisig configured
- [ ] Emergency procedures documented

# Deploy ALL contracts (use Ledger/Trezor)
forge script script/deploy/DeployAll.s.sol \\
  --rpc-url $MAINNET_RPC_URL \\
  --ledger \\
  --broadcast \\
  --verify

# Save the UserHub and AdminHub addresses from output
# Frontend needs UserHub, Admin needs AdminHub
```

## Post-Deployment

1. Transfer ownership to multisig
2. Verify all contracts on Etherscan
3. Enable monitoring alerts
4. Gradual rollout (whitelist → public)
5. 24/7 monitoring for first week

[To be expanded]
