---
title: "Phase 08: Update Documentation"
description: "Document amount parameter usage and provide code examples"
status: pending
priority: P2
effort: 0.5h
tags: [documentation, examples]
---

## Overview

Update SDK documentation to explain the `amount` parameter for ERC1155 listings and provide clear usage examples.

## Requirements

### Functional Requirements
1. Document `amount` parameter in `ListNFTParams`
2. Document `amounts` parameter in `BatchListNFTParams`
3. Provide ERC1155 usage examples
4. Document ERC721 backward compatibility
5. Update changelog with breaking changes (if any)

### Non-Functional Requirements
- Clear, concise documentation
- Practical code examples
- Migration guide for existing users

## Related Code Files

### Files to Create

**`E:\zuno-marketplace-sdk\docs\erc1155-listing-guide.md`**
- Comprehensive guide for ERC1155 listings

### Files to Update

**`E:\zuno-marketplace-sdk\README.md`**
- Add ERC1155 examples section

**`E:\zuno-marketplace-sdk\CHANGELOG.md`**
- Document changes in upcoming release

## Documentation Structure

### Section 1: Overview

```markdown
# ERC1155 Listing Support

The Zuno Marketplace SDK now supports listing ERC1155 NFTs with configurable amounts. ERC1155 tokens can represent multiple identical items, so you can specify how many tokens to list in a single listing.

## Key Differences: ERC721 vs ERC1155

| Feature | ERC721 | ERC1155 |
|---------|--------|---------|
| Amount Parameter | Not required (always 1) | Optional (defaults to 1) |
| Unique Items | Each token is unique | Tokens have IDs and amounts |
| Batch Listing | Multiple token IDs | Multiple token IDs + amounts |
```

### Section 2: Code Examples

#### Example 1: List Single ERC1155

```typescript
// List 10 ERC1155 tokens for sale
const { listingId, tx } = await sdk.exchange.listNFT({
  collectionAddress: '0x1234...erc1155',
  tokenId: '1',
  amount: '10',  // List 10 tokens
  price: '2.5',  // 2.5 ETH per token
  duration: 86400,  // 24 hours
});

console.log(`Created listing: ${listingId}`);
```

#### Example 2: List Single ERC1155 with Default Amount

```typescript
// amount defaults to '1' for ERC1155 if omitted
const { listingId, tx } = await sdk.exchange.listNFT({
  collectionAddress: '0x1234...erc1155',
  tokenId: '1',
  // amount: '1',  // Optional, defaults to 1
  price: '1.0',
  duration: 86400,
});
```

#### Example 3: Batch List ERC1155

```typescript
// List multiple ERC1155 tokens with different amounts
const { listingIds, tx } = await sdk.exchange.batchListNFT({
  collectionAddress: '0x1234...erc1155',
  tokenIds: ['1', '2', '3'],
  amounts: ['5', '10', '15'],  // 5 of token 1, 10 of token 2, 15 of token 3
  prices: ['1.0', '2.0', '3.0'],  // Per-token prices
  duration: 86400,
});

console.log(`Created ${listingIds.length} listings`);
```

#### Example 4: Batch List ERC1155 with Default Amounts

```typescript
// amounts defaults to array of '1's if omitted
const { listingIds, tx } = await sdk.exchange.batchListNFT({
  collectionAddress: '0x1234...erc1155',
  tokenIds: ['1', '2', '3'],
  // amounts: ['1', '1', '1'],  // Optional, defaults to [1, 1, 1]
  prices: ['1.0', '2.0', '3.0'],
  duration: 86400,
});
```

#### Example 5: ERC721 Backward Compatibility

```typescript
// ERC721 listings work exactly as before (no amount needed)
const { listingId, tx } = await sdk.exchange.listNFT({
  collectionAddress: '0x5678...erc721',
  tokenId: '42',
  price: '1.5',
  duration: 86400,
  // amount parameter not needed for ERC721
});
```

### Section 3: Getting Listing Details

```typescript
// Fetch listing details (includes amount for ERC1155)
const listing = await sdk.exchange.getListing(listingId);

console.log('Listing details:');
console.log('- Token ID:', listing.tokenId);
console.log('- Price:', listing.price, 'ETH');
console.log('- Amount:', listing.amount ?? 'N/A (ERC721)');  // undefined for ERC721
console.log('- Status:', listing.status);
```

### Section 4: Validation Rules

```markdown
## Amount Validation Rules

1. **Amount must be greater than 0**: `amount: '0'` will throw an error
2. **Amount must be a valid string number**: `amount: 'invalid'` will throw an error
3. **Batch amounts array length must match token IDs**: Mismatched lengths will throw an error
4. **Amount defaults to '1'**: If omitted for ERC1155, defaults to 1 token
5. **ERC721 ignores amount**: Amount parameter is not used for ERC721 listings
```

### Section 5: Error Handling

```typescript
import { ZunoSDKError, ErrorCodes } from '@zuno/sdk';

try {
  await sdk.exchange.listNFT({
    collectionAddress: '0x1234...erc1155',
    tokenId: '1',
    amount: '0',  // Invalid!
    price: '1.0',
    duration: 86400,
  });
} catch (error) {
  if (error instanceof ZunoSDKError) {
    if (error.code === ErrorCodes.INVALID_PARAMETER) {
      console.error('Invalid amount:', error.message);
      // Output: "Invalid amount: Amount must be greater than 0"
    }
  }
}
```

### Section 6: Migration Guide

```markdown
## Migration Guide for Existing SDK Users

### Do I need to change my code?

**No, if you only use ERC721**: Your existing code will continue to work without changes.

**Yes, if you use ERC1155**: You need to add the `amount` parameter when listing.

### Before (v1.x)

```typescript
// This would fail for ERC1155 in v1.x
const { listingId } = await sdk.exchange.listNFT({
  collectionAddress: '0x1234...erc1155',
  tokenId: '1',
  price: '1.0',
  duration: 86400,
});
```

### After (v2.x)

```typescript
// Now works for ERC1155 with optional amount parameter
const { listingId } = await sdk.exchange.listNFT({
  collectionAddress: '0x1234...erc1155',
  tokenId: '1',
  amount: '10',  // Specify amount for ERC1155
  price: '1.0',
  duration: 86400,
});

// ERC721 code remains unchanged
const { listingId: erc721Listing } = await sdk.exchange.listNFT({
  collectionAddress: '0x5678...erc721',
  tokenId: '42',
  price: '1.0',
  duration: 86400,
  // No amount needed for ERC721
});
```

### Breaking Changes

**None**: The `amount` parameter is optional, so existing code remains compatible.
```

### Section 7: FAQ

```markdown
## Frequently Asked Questions

**Q: Do I need to specify amount for ERC721 listings?**
A: No, ERC721 listings don't use the amount parameter. Each ERC721 token is unique.

**Q: What happens if I don't specify amount for ERC1155?**
A: The SDK will default to `amount: '1'`, listing a single token.

**Q: Can I list partial amounts from my ERC1155 balance?**
A: Yes, you can list any amount up to your current balance. The contract will validate you have sufficient tokens.

**Q: How do I know if a collection is ERC721 or ERC1155?**
A: The SDK auto-detects the token standard using ERC165. You don't need to specify it manually.

**Q: Can I buy partial amounts from an ERC1155 listing?**
A: Yes, ERC1155 supports partial purchases. You can buy less than the full listed amount.
```

## Success Criteria

- [ ] README updated with ERC1155 examples
- [ ] ERC1155 listing guide created
- [ ] API documentation updated (JSDoc comments)
- [ ] Changelog updated with changes
- [ ] Migration guide available
- [ ] FAQ section covers common questions

## Next Steps

After documentation, all phases are complete. Proceed to implementation.

## References

- Existing Docs: `E:\zuno-marketplace-sdk\README.md`
- Debugger Report: Issue 4 (Documentation needed)
- Contract Docs: ERC1155 supports fractional/partial purchases
