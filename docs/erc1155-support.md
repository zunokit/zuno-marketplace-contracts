# ERC1155 Support in Zuno Marketplace

**Last Updated:** 2026-01-22
**Contract Version:** Solidity ^0.8.30

---

## Overview

Zuno Marketplace provides comprehensive support for ERC1155 tokens with advanced features including partial purchases, proportional pricing, and automatic listing management. ERC1155 tokens can represent fungible or semi-fungible assets, making them ideal for gaming items, event tickets, and collectibles with multiple copies.

## Key Differences: ERC721 vs ERC1155

| Feature | ERC721 | ERC1155 |
|---------|--------|---------|
| Token Uniqueness | Each token is unique | Tokens have IDs and amounts |
| Amount Parameter | Not applicable | Required (must be > 0) |
| Purchase Type | Entire token only | Full or partial amount |
| Pricing | Fixed per token | Proportional to amount |
| Listing Status | SOLD after purchase | Sold only when amount reaches 0 |

## Smart Contract Functions

### ERC1155NFTExchange.sol

**File:** `src/core/exchange/ERC1155NFTExchange.sol` (344 lines)

#### List Single ERC1155

```solidity
function listNFT(
    address m_contractAddress,
    uint256 m_tokenId,
    uint256 m_amount,      // Amount to list (must be > 0)
    uint256 m_price,       // Total price for all tokens
    uint256 m_listingDuration
) public
```

**Validation:**
- `amount > 0`: Reverts with `NFTExchange__AmountMustBeGreaterThanZero()`
- `price > 0`: Reverts with `NFTExchange__PriceMustBeGreaterThanZero()`
- `duration > 0`: Reverts with `NFTExchange__DurationMustBeGreaterThanZero()`
- Sufficient balance: Reverts with `NFTExchange__InsufficientBalance()`
- Marketplace approved: Reverts with `NFTExchange__MarketplaceNotApproved()`

#### Batch List ERC1155

```solidity
function batchListNFT(
    address m_contractAddress,
    uint256[] memory m_tokenIds,
    uint256[] memory m_amounts,    // Amount per token ID
    uint256[] memory m_prices,     // Price per token ID
    uint256 m_listingDuration
) public
```

**Validation:**
- Array lengths must match: Reverts with `NFTExchange__ArrayLengthMismatch()`
- All amounts > 0: Reverts with `NFTExchange__AmountMustBeGreaterThanZero()`
- All prices > 0: Reverts with `NFTExchange__PriceMustBeGreaterThanZero()`

#### Purchase Full Listing

```solidity
function buyNFT(bytes32 m_listingId) public payable
```

Purchases the entire amount listed. Calculates total price including fees.

#### Purchase Partial Amount

```solidity
function buyNFT(bytes32 m_listingId, uint256 m_amount) public payable
```

**Validation:**
- `amount > 0`: Reverts with `NFTExchange__AmountMustBeGreaterThanZero()`
- `amount <= listing.amount`: Reverts with `NFTExchange__InsufficientBalance()`

**Proportional Pricing:**
```solidity
proportionalPrice = (listing.price * purchaseAmount) / listing.amount
```

#### Batch Purchase

```solidity
function batchBuyNFT(bytes32[] memory m_listingIds) public payable
```

Purchases entire listings in batch. All listings must be from the same collection.

## Data Flow

### Listing Creation Flow

```
Seller calls listNFT()
    │
    ├─→ Validate amount > 0
    ├─→ Validate price > 0
    ├─→ Validate duration > 0
    │
    ├─→ Validate ownership (balanceOf)
    ├─→ Validate approval (isApprovedForAll)
    │
    ├─→ Generate listing ID
    │   └─→ keccak256(abi.encodePacked(contract, tokenId, seller, timestamp))
    │
    ├─→ Store listing with amount
    │   └─→ s_listings[listingId] = Listing{..., amount}
    │
    ├─→ Track history
    │   └─→ ListingHistoryTracker.track()
    │
    └─→ Emit NFTListed event
```

### Purchase Flow (Partial)

```
Buyer calls buyNFT(listingId, amount)
    │
    ├─→ Validate listing active
    ├─→ Validate amount > 0
    ├─→ Validate amount <= listing.amount
    │
    ├─→ Calculate proportional price
    │   └─→ (listing.price * amount) / listing.amount
    │
    ├─→ Calculate fees (royalty + platform)
    ├─→ Validate payment >= total
    │
    ├─→ Transfer NFTs to buyer
    │   └─→ ERC1155.safeTransferFrom(seller, buyer, tokenId, amount, "")
    │
    ├─→ Distribute payments
    │   ├─→ Royalty to creator
    │   ├─→ Platform fee to marketplace
    │   └─→ Remainder to seller
    │
    ├─→ Update listing amount
    │   └─→ listing.amount -= amount
    │
    ├─→ Check finalization
    │   │
    │   ├─→ If listing.amount == 0:
    │   │       ├─→ status = SOLD
    │   │       └─→ Emit ListingSold event
    │   │
    │   └─→ If listing.amount > 0:
    │           └─→ Emit NFTSold event (listing remains active)
    │
    └─→ Track history
```

## Event Emission

### Full Sale
```solidity
emit ListingSold(
    listingId,
    contractAddress,
    tokenId,
    seller,
    buyer,
    price  // Full listing price
);
```

### Partial Sale (ERC1155 only)
```solidity
emit NFTSold(
    listingId,
    contractAddress,
    tokenId,
    seller,
    buyer,
    proportionalPrice  // Price for purchased amount
);
```

**Note:** The listing remains `ACTIVE` after a partial sale. The `ListingSold` event is only emitted when `listing.amount` reaches 0.

## Validation Rules

### Amount Validation
1. **Listing**: `amount` must be > 0
2. **Purchase**: Purchase amount must be > 0
3. **Purchase**: Purchase amount must be ≤ listing amount
4. **Batch**: Array lengths must match

### Balance Validation
- `IERC1155(contract).balanceOf(seller, tokenId) >= amount`
- Reverts with `NFTExchange__InsufficientBalance()`

### Approval Validation
- `IERC1155(contract).isApprovedForAll(seller, marketplace) == true`
- Reverts with `NFTExchange__MarketplaceNotApproved()`

## Gas Costs

| Operation | Gas Cost |
|-----------|----------|
| List ERC1155 (single) | ~120k gas |
| List ERC1155 (batch, 5 items) | ~350k gas |
| Buy ERC1155 (full) | ~160k gas |
| Buy ERC1155 (partial) | ~165k gas |
| Cancel listing | ~50k gas |

## SDK Integration

The SDK (`@zuno/sdk`) handles ERC1155 interactions seamlessly:

```typescript
// List ERC1155 with amount
const { listingId } = await sdk.exchange.listNFT({
  collectionAddress: '0x123...',
  tokenId: '1',
  amount: '10',  // 10 tokens
  price: '2.5',  // 2.5 ETH for all 10 tokens
  duration: 86400,
});

// Buy full listing
await sdk.exchange.buyNFT({ listingId });

// Buy partial amount
await sdk.exchange.buyNFT({
  listingId,
  amount: '3',  // Buy 3 out of 10 tokens
});

// Price automatically calculated: (2.5 * 3) / 10 = 0.75 ETH
```

## Error Handling

### Custom Errors

| Error | Condition |
|-------|-----------|
| `NFTExchange__AmountMustBeGreaterThanZero()` | amount == 0 |
| `NFTExchange__InsufficientBalance()` | Insufficient token balance |
| `NFTExchange__InsufficientPayment()` | Payment too low |
| `NFTExchange__ArrayLengthMismatch()` | Array lengths don't match (batch) |
| `NFTExchange__MarketplaceNotApproved()` | Marketplace not approved |

## Security Considerations

### Reentrancy Protection
- All purchase functions use `nonReentrant` modifier
- Checks-Effects-Interactions pattern enforced

### Integer Overflow
- Uses `unchecked` block for safe arithmetic operations
- Proportional price calculation protected by Solidity 0.8+ built-in overflow checks

### Validation
- Amount validation prevents zero-value listings
- Balance checks prevent listing unowned tokens
- Approval checks ensure marketplace can transfer

## Testing

### Test Coverage
- **Unit Tests**: `test/unit/exchange/ERC1155NFTExchange.t.sol`
- **Integration Tests**: `test/integration/BasicWorkflows.t.sol`
- **Edge Cases**: Zero amounts, partial purchases, full sales

### Key Test Scenarios
1. List single ERC1155 with amount
2. Purchase entire listing
3. Purchase partial amount
4. Multiple partial purchases until sold out
5. Batch listing and purchase
6. Validation failures (zero amount, insufficient balance)

## Migration from ERC721

### No Breaking Changes
ERC721 functionality remains unchanged. ERC1155 is a separate contract with additional features.

### For Developers
- ERC721: Use `ERC721NFTExchange`
- ERC1155: Use `ERC1155NFTExchange`
- Auto-detection: Use `UserHub.getExchangeFor(collection)`

## Limitations

1. **Single Collection**: Batch operations require same collection
2. **No Fractional Purchases**: Must purchase whole tokens (integer amounts)
3. **Price Calculation**: Proportional pricing may have rounding (uses integer division)

## Future Enhancements

- [ ] Cross-collection batch operations
- [ ] Fractional token support (if standard emerges)
- [ ] Advanced pricing models (tiered, volume discounts)
- [ ] Listing amount updates

---

**Document Owner:** Development Team
**Related Docs:**
- [System Architecture](./system-architecture.md)
- [Codebase Summary](./codebase-summary.md)
- [Project Overview](./project-overview-pdr.md)
