# Zuno Marketplace Contracts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.30-blue.svg)](https://docs.soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-992%2F992%20Passing-brightgreen.svg)](#testing)

A production-ready, modular NFT marketplace smart contract system built with Foundry. Supports ERC721 & ERC1155 tokens with advanced trading features including auctions, offers, bundles, and comprehensive collection management with a unified Hub architecture.

## Features

- **Multi-token Support**: ERC721 and ERC1155 collections with automatic standard detection
- **Advanced Trading**: Direct sales, English/Dutch auctions, offers, and bundle trading
- **Hub Architecture**: Dual hub pattern (AdminHub for admin ops, UserHub for frontend integration)
- **Gas Optimized**: Minimal proxy pattern (~100x deployment savings), custom errors, packed storage
- **Security First**: RBAC, reentrancy guards, emergency controls, 48-hour timelock
- **EIP-2981 Compliant**: Universal royalty support across marketplaces

## Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- [Node.js](https://nodejs.org/) (v18+) and [pnpm](https://pnpm.io/)

### Installation

```bash
# Clone repository
git clone https://github.com/ZunoKit/zuno-marketplace-contracts.git
cd zuno-marketplace-contracts

# Install dependencies
forge install
pnpm install

# Build contracts
forge build
```

### Local Development

```bash
# Start local blockchain
anvil --port 8545

# Deploy contracts
make deploy-all-local

# Run tests
forge test
```

## Documentation

**Comprehensive documentation available in `/docs`:**

- **[Project Overview & PDR](./docs/project-overview-pdr.md)** - Executive summary, product vision, requirements, and success metrics
- **[Codebase Summary](./docs/codebase-summary.md)** - Complete contract inventory, module descriptions, and patterns
- **[System Architecture](./docs/system-architecture.md)** - Dual Hub pattern, data flows, security architecture
- **[Code Standards](./docs/code-standards.md)** - Naming conventions, testing standards, best practices
- **[User Guide](./docs/user-guide.md)** - Frontend integration with UserHub and examples
- **[Security](./docs/security/)** - Security patterns, access control, audit preparation
- **[API Reference](./docs/api/)** - Contract APIs and interfaces
- **[Deployment Guide](./docs/deployment/)** - Production deployment procedures

### Key Architecture: Dual Hub Pattern

**AdminHub** - Admin operations (registrations, configuration, emergency controls)
**UserHub** - Frontend integration (address discovery, auto-detection, queries)

**Frontend Integration:**
```typescript
// 1. Initialize with UserHub only
const hub = new Contract(USER_HUB, UserHubABI, provider);

// 2. Get all addresses
const { erc721Exchange, erc1155Exchange, ... } = await hub.getAllAddresses();

// 3. Auto-detect exchange for any NFT
const exchangeAddr = await hub.getExchangeFor(nftContract);
```

See [System Architecture](./docs/system-architecture.md) for complete details.

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Coverage report
forge coverage

# Gas snapshots
forge snapshot
```

**Test Coverage:** 992/992 tests passing (100%)

## Project Structure

```
src/
├── core/              # Core marketplace contracts (20 contracts)
│   ├── access/        # Role-based access control
│   ├── analytics/     # History tracking
│   ├── auction/       # English & Dutch auctions
│   ├── collection/    # Collection management
│   ├── exchange/      # ERC721/1155 trading
│   ├── factory/       # Gas-efficient factories
│   ├── fees/          # Fee & royalty management
│   ├── listing/       # Advanced listings
│   ├── offers/        # Offer system
│   ├── security/      # Emergency & timelock
│   └── validation/    # Input validation
├── router/            # AdminHub + UserHub
├── registry/          # Exchange, Collection, Auction, Fee registries
├── common/            # Base contracts
├── libraries/         # 8 reusable libraries
├── interfaces/        # 16 interface definitions
├── types/             # Struct definitions
├── events/            # Event definitions
└── errors/            # 500+ custom errors
```

See [Codebase Summary](./docs/codebase-summary.md) for complete contract inventory.

## Deployment

### Deploy Everything (Recommended)

```bash
forge script script/deploy/DeployAll.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

**Output:** AdminHub and UserHub addresses (frontend needs UserHub)

### Environment Variables

Create `.env`:
```bash
MARKETPLACE_WALLET=0x...  # Admin address
PRIVATE_KEY=0x...          # Deployer key
SEPOLIA_RPC_URL=https://...
MAINNET_RPC_URL=https://...
```

## Architecture Highlights

### Gas Optimization
- **Minimal Proxies**: ~100x deployment savings for collections/auctions
- **Custom Errors**: ~50 gas savings per revert (500+ errors)
- **Storage Packing**: Optimized struct layouts
- **Libraries**: Code reuse via 8 specialized libraries

### Security Features
- **RBAC**: 6 roles with granular permissions
- **Reentrancy Guards**: All state-changing functions protected
- **Emergency Controls**: Global pause/unpause
- **Timelock**: 48-hour delay on critical changes
- **Input Validation**: Dedicated validator contracts

### Trading Features
- **Fixed-Price Sales**: Instant ERC721/1155 trading
- **English Auctions**: Highest-bidder-wins with automatic refunds
- **Dutch Auctions**: Descending price auctions
- **Offers**: Make offers on any NFT
- **Bundles**: Trade multiple NFTs together

## Common Commands

```bash
# Build
forge build

# Test
forge test              # All tests
forge test -vv          # With failure logs
forge test -vvv         # With stack traces

# Format
forge fmt               # Format code
forge fmt --check       # Check formatting

# Gas
forge test --gas-report # Gas report
forge snapshot          # Gas snapshots

# Coverage
forge coverage          # Coverage report
```

## Development Standards

**This project follows RED-GREEN-REFACTOR methodology:**

1. **RED**: Write failing tests first
2. **GREEN**: Write minimal code to pass tests
3. **REFACTOR**: Improve code while keeping tests passing

**See [Code Standards](./docs/code-standards.md) for complete guidelines.**

## Status

✅ **Development Complete** - All features implemented
✅ **Testing Complete** - 992/992 tests passing (100%)
⚠️ **Audit Pending** - Professional security audit required before production

## Contributing

We welcome contributions! Please see [Code Standards](./docs/code-standards.md) for contribution guidelines.

**Process:**
1. Fork and create feature branch
2. Write tests for your changes (RED phase)
3. Implement code to pass tests (GREEN phase)
4. Refactor while keeping tests passing (REFACTOR phase)
5. Submit PR with conventional commit format

**Commit Format:**
```
<type>(<scope>): <description>

feat(exchange): add bundle trading
fix(auction): prevent bid overflow
docs(readme): update installation
```

## Support

- **Documentation**: See `/docs` directory
- **Issues**: [GitHub Issues](https://github.com/ZunoKit/zuno-marketplace-contracts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ZunoKit/zuno-marketplace-contracts/discussions)

## License

MIT License - see [LICENSE](LICENSE) file.

## Disclaimer

⚠️ **This software is provided "as is", without warranty.** This is a financial application handling user assets. Always conduct thorough testing and professional security audits before production use.

**NOT YET AUDITED** - Do not use in production without professional security audit.

---

**Built with ❤️ using Foundry**
