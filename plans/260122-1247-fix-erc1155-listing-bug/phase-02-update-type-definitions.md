---
title: "Phase 02: Update Type Definitions"
description: "Add optional amount field to listing parameter types and Listing entity"
status: pending
priority: P1
effort: 0.5h
tags: [types, interfaces]
---

## Overview

Add optional `amount` field to `ListNFTParams`, `BatchListNFTParams`, and `Listing` interface to support ERC1155 listings while maintaining backward compatibility with ERC721.

## Requirements

### Functional Requirements
1. Add `amount?: string` to `ListNFTParams`
2. Add `amounts?: string[]` to `BatchListNFTParams`
3. Add `amount?: string` to `Listing` entity
4. Maintain backward compatibility (optional fields)

### Non-Functional Requirements
- TypeScript type safety
- No breaking changes for existing SDK users
- Clear documentation in JSDoc comments

## Related Code Files

### Files to Modify

**`E:\zuno-marketplace-sdk\src\types\contracts.ts`**
- Lines 87-93: Update `ListNFTParams` interface
- Lines 98-103: Update `BatchListNFTParams` interface

**`E:\zuno-marketplace-sdk\src\types\entities.ts`**
- Lines 50-61: Update `Listing` interface

## Implementation Steps

### Step 1: Update ListNFTParams

**File:** `src/types/contracts.ts:87-93`

```typescript
export interface ListNFTParams {
  /**
   * NFT collection contract address
   */
  collectionAddress: string;

  /**
   * Token ID to list
   */
  tokenId: string;

  /**
   * Listing price in ETH (e.g., "1.5")
   */
  price: string;

  /**
   * Listing duration in seconds
   */
  duration: number;

  /**
   * Amount of tokens to list (for ERC1155 only)
   * @default "1"
   * @example "10" for 10 ERC1155 tokens
   */
  amount?: string;

  /**
   * Transaction options (gas limit, gas price, etc.)
   */
  options?: TransactionOptions;
}
```

### Step 2: Update BatchListNFTParams

**File:** `src/types/contracts.ts:98-103`

```typescript
export interface BatchListNFTParams {
  /**
   * NFT collection contract address (must be same for all tokens)
   */
  collectionAddress: string;

  /**
   * Array of token IDs to list
   */
  tokenIds: string[];

  /**
   * Array of prices in ETH (one per token ID)
   */
  prices: string[];

  /**
   * Listing duration in seconds (same for all)
   */
  duration: number;

  /**
   * Array of amounts (for ERC1155 only)
   * Length must match tokenIds.length
   * @example ["1", "5", "10"] for 3 tokens with different amounts
   */
  amounts?: string[];

  /**
   * Transaction options
   */
  options?: TransactionOptions;
}
```

### Step 3: Update Listing Entity

**File:** `src/types/entities.ts:50-61`

```typescript
export interface Listing {
  /**
   * Listing ID (bytes32)
   */
  id: string;

  /**
   * Seller address
   */
  seller: string;

  /**
   * NFT collection address
   */
  collectionAddress: string;

  /**
   * Token ID
   */
  tokenId: string;

  /**
   * Listing price in ETH
   */
  price: string;

  /**
   * Payment token address (ETH = ZeroAddress)
   */
  paymentToken: string;

  /**
   * Listing start timestamp (Unix)
   */
  startTime: number;

  /**
   * Listing end timestamp (Unix)
   */
  endTime: number;

  /**
   * Listing status
   */
  status: 'pending' | 'active' | 'sold' | 'cancelled' | 'expired';

  /**
   * Listing creation timestamp (ISO 8601)
   */
  createdAt: string;

  /**
   * Amount of tokens listed (ERC1155 only)
   * undefined for ERC721 listings
   */
  amount?: string;
}
```

## Success Criteria

- [ ] TypeScript compiles without errors
- [ ] Existing ERC721 code still compiles (backward compatibility)
- [ ] JSDoc comments clearly explain amount parameter
- [ ] No runtime errors from type changes

## Security Considerations

- Type system only - no runtime impact
- Optional fields prevent breaking changes
- String type for amount (BigNumber compatibility)

## Next Steps

Proceed to Phase 03: Implement single listing fix in `listNFT()`.

## References

- Debugger Report: Issue 3 & 4 (Type definitions missing amount field)
- Contract Listing struct: `BaseNFTExchange.sol` includes `uint256 amount`
