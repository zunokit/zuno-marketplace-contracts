---
title: "Phase 05: Update Listing Entity"
description: "Extract amount field from contract data in formatListing()"
status: pending
priority: P2
effort: 0.5h
tags: [implementation, formatListing, entities]
---

## Overview

Update `formatListing()` function to extract the `amount` field from contract listing data and include it in the returned `Listing` entity.

## Requirements

### Functional Requirements
1. Extract `amount` field from contract listing struct
2. Include amount in returned Listing entity
3. Handle missing amount gracefully (undefined for old data)
4. Convert amount BigInt to string for consistency

### Non-Functional Requirements
- Maintain existing formatListing behavior
- No breaking changes to existing code
- Consistent data types

## Related Code Files

### Files to Modify

**`E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts`**
- Lines 519-556: `formatListing()` function

## Contract Listing Struct

**From BaseNFTExchange.sol:**
```solidity
struct Listing {
    address contractAddress;
    uint256 tokenId;
    uint256 price;
    address seller;
    uint256 listingDuration;
    uint256 listingStart;
    ListingStatus status;
    uint256 amount;  // <-- This field exists in contract
}
```

## Implementation Steps

### Step 1: Update formatListing() Function

**File:** `src/modules/ExchangeModule.ts:519-556`

**Current Code:**
```typescript
private formatListing(id: string, data: ethers.Result): Listing {
  const contractAddress = String(data.contractAddress);
  const tokenId = BigInt(data.tokenId);
  const price = BigInt(data.price);
  const seller = String(data.seller);
  const listingDuration = BigInt(data.listingDuration);
  const listingStart = BigInt(data.listingStart);
  const status = Number(data.status);

  // Contract enum: 0=Pending, 1=Active, 2=Sold, 3=Failed, 4=Cancelled
  const statusMap: Record<number, Listing['status']> = {
    0: 'pending',
    1: 'active',
    2: 'sold',
    3: 'expired',
    4: 'cancelled',
  };

  const startTime = Number(listingStart);
  const endTime = startTime + Number(listingDuration);

  return {
    id,
    seller,
    collectionAddress: contractAddress,
    tokenId: tokenId.toString(),
    price: ethers.formatEther(price),
    paymentToken: ethers.ZeroAddress,
    startTime,
    endTime,
    status: statusMap[status] || 'active',
    createdAt: new Date(startTime * 1000).toISOString(),
  };
}
```

**Updated Code:**
```typescript
private formatListing(id: string, data: ethers.Result): Listing {
  const contractAddress = String(data.contractAddress);
  const tokenId = BigInt(data.tokenId);
  const price = BigInt(data.price);
  const seller = String(data.seller);
  const listingDuration = BigInt(data.listingDuration);
  const listingStart = BigInt(data.listingStart);
  const status = Number(data.status);

  // Extract amount field (present in contract struct)
  // Convert to string for consistency with other BigNumber fields
  const amount = data.amount
    ? BigInt(data.amount).toString()
    : undefined;

  // Contract enum: 0=Pending, 1=Active, 2=Sold, 3=Failed, 4=Cancelled
  const statusMap: Record<number, Listing['status']> = {
    0: 'pending',
    1: 'active',
    2: 'sold',
    3: 'expired',
    4: 'cancelled',
  };

  const startTime = Number(listingStart);
  const endTime = startTime + Number(listingDuration);

  return {
    id,
    seller,
    collectionAddress: contractAddress,
    tokenId: tokenId.toString(),
    price: ethers.formatEther(price),
    paymentToken: ethers.ZeroAddress,
    startTime,
    endTime,
    status: statusMap[status] || 'active',
    createdAt: new Date(startTime * 1000).toISOString(),
    amount,  // Include amount in returned Listing
  };
}
```

### Step 2: Update Comment

**Line 521** - Update the function comment:

```typescript
/**
 * Format raw listing data from contract
 *
 * Contract struct includes:
 * - contractAddress, tokenId, price, seller
 * - listingDuration, listingStart, status, amount
 *
 * @param id - Listing ID (bytes32)
 * @param data - Raw contract data (ethers.Result)
 * @returns Formatted Listing entity
 */
private formatListing(id: string, data: ethers.Result): Listing {
```

## Key Insights

1. **Amount Field Exists**: Contract struct already includes `uint256 amount`
2. **Extraction Missing**: SDK wasn't extracting this field
3. **Optional in Entity**: `amount?: string` handles both ERC721 (undefined) and ERC1155 (value)
4. **String Conversion**: Convert BigInt to string for JSON consistency
5. **Graceful Handling**: Use ternary to handle undefined data.amount

## Success Criteria

- [ ] Amount field extracted from contract data
- [ ] ERC1155 listings show correct amount
- [ ] ERC721 listings have amount = undefined
- [ ] No errors when data.amount is missing (old listings)
- [ ] TypeScript compiles without errors

## Security Considerations

- BigInt conversion prevents overflow errors
- Optional field handles missing data gracefully
- No trust assumptions on contract data
- Consistent with other BigNumber fields (price, tokenId)

## Testing Strategy

**Test Cases:**
1. Get ERC1155 listing (should have amount)
2. Get ERC721 listing (amount should be undefined)
3. Handle missing data.amount gracefully

**Expected Behavior:**
- ERC1155: `listing.amount === '10'` (for example)
- ERC721: `listing.amount === undefined`

## Next Steps

Proceed to Phase 06: Add validation for amount parameter.

## References

- Debugger Report: Issue 4 (Listing entity missing amount field)
- Contract Listing Struct: BaseNFTExchange.sol includes `uint256 amount`
- Current Comment (line 521): Already mentions amount in comment but doesn't extract it
