---
title: "Phase 06: Add Validation"
description: "Add validation logic for amount parameter in listing functions"
status: pending
priority: P2
effort: 0.5h
tags: [validation, error-handling]
---

## Overview

Add validation logic to ensure amount parameter is valid for ERC1155 listings and provide clear error messages.

## Requirements

### Functional Requirements
1. Validate amount > 0 for ERC1155 listings
2. Validate amounts array length matches tokenIds array length
3. Validate each amount > 0 in batch listings
4. Provide clear error messages for validation failures

### Non-Functional Requirements
- Fail fast with clear errors
- Prevent unnecessary RPC calls for invalid input
- Consistent with existing validation patterns

## Related Code Files

### Files to Modify

**`E:\zuno-marketplace-sdk\src\utils\errors.ts`**
- Update `validateListNFTParams()` function
- Add `validateBatchListNFTParams()` function (if doesn't exist)

## Implementation Steps

### Step 1: Update validateListNFTParams()

**File:** `src/utils/errors.ts`

```typescript
export function validateListNFTParams(params: ListNFTParams): void {
  if (!params.collectionAddress || !ethers.isAddress(params.collectionAddress)) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_ADDRESS,
      'Invalid collection address'
    );
  }

  if (!params.tokenId || params.tokenId === '0') {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Token ID must be greater than 0'
    );
  }

  if (!params.price || parseFloat(params.price) <= 0) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Price must be greater than 0'
    );
  }

  if (!params.duration || params.duration <= 0) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Duration must be greater than 0'
    );
  }

  // Validate amount if provided
  if (params.amount !== undefined) {
    try {
      const amount = BigInt(params.amount);
      if (amount <= 0) {
        throw new ZunoSDKError(
          ErrorCodes.INVALID_PARAMETER,
          'Amount must be greater than 0'
        );
      }
    } catch (error) {
      throw new ZunoSDKError(
        ErrorCodes.INVALID_PARAMETER,
        'Invalid amount format'
      );
    }
  }
}
```

### Step 2: Add validateBatchListNFTParams()

**File:** `src/utils/errors.ts`

```typescript
export function validateBatchListNFTParams(params: BatchListNFTParams): void {
  if (!params.collectionAddress || !ethers.isAddress(params.collectionAddress)) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_ADDRESS,
      'Invalid collection address'
    );
  }

  if (!params.tokenIds || params.tokenIds.length === 0) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Token IDs array cannot be empty'
    );
  }

  if (!params.prices || params.prices.length === 0) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Prices array cannot be empty'
    );
  }

  if (params.tokenIds.length !== params.prices.length) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Token IDs and prices arrays must have the same length'
    );
  }

  if (!params.duration || params.duration <= 0) {
    throw new ZunoSDKError(
      ErrorCodes.INVALID_PARAMETER,
      'Duration must be greater than 0'
    );
  }

  // Validate amounts array if provided
  if (params.amounts !== undefined) {
    if (params.amounts.length !== params.tokenIds.length) {
      throw new ZunoSDKError(
        ErrorCodes.INVALID_PARAMETER,
        'Amounts array must have the same length as token IDs array'
      );
    }

    // Validate each amount > 0
    for (let i = 0; i < params.amounts.length; i++) {
      try {
        const amount = BigInt(params.amounts[i]);
        if (amount <= 0) {
          throw new ZunoSDKError(
            ErrorCodes.INVALID_PARAMETER,
            `Amount at index ${i} must be greater than 0`
          );
        }
      } catch (error) {
        throw new ZunoSDKError(
          ErrorCodes.INVALID_PARAMETER,
          `Invalid amount format at index ${i}`
        );
      }
    }
  }
}
```

### Step 3: Call Validation in ExchangeModule

**File:** `src/modules/ExchangeModule.ts`

**In `batchListNFT()` function (line ~561):**
```typescript
async batchListNFT(params: BatchListNFTParams): Promise<{ listingIds: string[]; tx: TransactionReceipt }> {
  // Add validation call at the start
  validateBatchListNFTParams(params);

  // ... rest of function ...
}
```

**Note:** `listNFT()` already calls `validateListNFTParams()` at line 134.

## Key Insights

1. **Fail Fast**: Validate before RPC calls to save gas/time
2. **Clear Messages**: Include index in array validation errors
3. **BigInt Handling**: Use BigInt for safe number parsing
4. **Optional Validation**: Only validate if amount provided
5. **Consistent Pattern**: Match existing validation style

## Success Criteria

- [ ] Amount = '0' rejected with clear error
- [ ] Amount = '-1' rejected with clear error
- [ ] Amounts array length mismatch rejected
- [ ] Invalid BigInt format rejected
- [ ] Validation runs before contract calls

## Security Considerations

- Input validation prevents contract reverts
- BigInt parsing handles arbitrary precision
- No integer overflow possible with BigInt
- Clear errors prevent confusion

## Testing Strategy

**Test Cases:**
1. List with amount='0' → Should fail
2. List with amount='-1' → Should fail
3. List with amount='invalid' → Should fail
4. Batch with amounts.length !== tokenIds.length → Should fail
5. Batch with amounts=['1', '0', '5'] → Should fail at index 1
6. Valid inputs → Should pass validation

## Next Steps

Proceed to Phase 07: Write comprehensive tests for all scenarios.

## References

- Existing Validation: `src/utils/errors.ts`
- Debugger Report: Suggested validation approach (Issue 4)
- Contract Validation: ERC1155 contract reverts on amount == 0
