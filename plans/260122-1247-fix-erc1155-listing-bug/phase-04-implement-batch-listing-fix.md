---
title: "Phase 04: Implement Batch Listing Fix"
description: "Update batchListNFT() to support ERC1155 amounts array"
status: pending
priority: P1
effort: 1.5h
tags: [implementation, batchListNFT, erc1155]
---

## Overview

Update `batchListNFT()` function to detect token standard and pass correct parameter array (4 params for ERC721, 5 params for ERC1155 including amounts array).

## Requirements

### Functional Requirements
1. Detect token standard before batch listing
2. Pass 4 params to ERC721 contract
3. Pass 5 params to ERC1155 contract (including amounts array)
4. Default amounts to array of '1's for ERC1155 if omitted
5. Validate array lengths match (tokenIds.length === amounts.length)
6. Maintain backward compatibility for ERC721

### Non-Functional Requirements
- Minimal performance impact
- Clear error messages
- Array length validation

## Related Code Files

### Files to Modify

**`E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts`**
- Lines 561-597: `batchListNFT()` function

## Implementation Steps

### Step 1: Update batchListNFT() Function

**File:** `src/modules/ExchangeModule.ts:561-597`

**Current Code:**
```typescript
async batchListNFT(params: BatchListNFTParams): Promise<{ listingIds: string[]; tx: TransactionReceipt }> {
  const { collectionAddress, tokenIds, prices, duration, options } = params;

  if (tokenIds.length === 0) {
    throw this.error(ErrorCodes.INVALID_PARAMETER, 'Token IDs array cannot be empty');
  }
  if (tokenIds.length !== prices.length) {
    throw this.error(ErrorCodes.INVALID_PARAMETER, 'Token IDs and prices arrays must have same length');
  }

  const normalizedCollection = validateAddress(collectionAddress);
  const txManager = this.ensureTxManager();
  const provider = this.ensureProvider();
  const sellerAddress = this.signer ? await this.signer.getAddress() : ethers.ZeroAddress;

  await this.ensureApproval(normalizedCollection, sellerAddress);

  const exchangeContract = await this.getExchangeContract(
    normalizedCollection,
    provider,
    this.signer
  );

  const pricesInWei = prices.map(p => ethers.parseEther(p));

  const tx = await txManager.sendTransaction(
    exchangeContract,
    'batchListNFT',
    [normalizedCollection, tokenIds, pricesInWei, duration],  // <-- ALWAYS 4 PARAMS
    { ...options, module: 'Exchange' }
  );

  const listingIds = this.extractListingIdsFromLogs(tx);
  return { listingIds, tx };
}
```

**Updated Code:**
```typescript
async batchListNFT(params: BatchListNFTParams): Promise<{ listingIds: string[]; tx: TransactionReceipt }> {
  const { collectionAddress, tokenIds, prices, duration, amounts, options } = params;

  if (tokenIds.length === 0) {
    throw this.error(ErrorCodes.INVALID_PARAMETER, 'Token IDs array cannot be empty');
  }
  if (tokenIds.length !== prices.length) {
    throw this.error(ErrorCodes.INVALID_PARAMETER, 'Token IDs and prices arrays must have same length');
  }

  // Validate amounts array length if provided
  if (amounts !== undefined && amounts.length !== tokenIds.length) {
    throw this.error(
      ErrorCodes.INVALID_PARAMETER,
      'Amounts array length must match token IDs array length'
    );
  }

  const normalizedCollection = validateAddress(collectionAddress);
  const txManager = this.ensureTxManager();
  const provider = this.ensureProvider();
  const sellerAddress = this.signer ? await this.signer.getAddress() : ethers.ZeroAddress;

  await this.ensureApproval(normalizedCollection, sellerAddress);

  // Detect token standard to determine correct parameters
  const tokenType: TokenStandard = await this.contractRegistry.verifyTokenStandard(
    normalizedCollection,
    provider
  );

  this.log('Detected token type for batch listing', { collectionAddress: normalizedCollection, tokenType });

  const exchangeContract = await this.getExchangeContract(
    normalizedCollection,
    provider,
    this.signer
  );

  const pricesInWei = prices.map(p => ethers.parseEther(p));

  // Prepare amounts array (default to array of '1's for ERC1155)
  const normalizedAmounts = amounts || tokenIds.map(() => '1');

  // Prepare parameters based on token type
  const contractParams = tokenType === 'ERC1155'
    ? [
        normalizedCollection,
        tokenIds,
        normalizedAmounts,  // ERC1155: amounts array
        pricesInWei,
        duration,
      ]  // ERC1155: 5 params (address, uint256[], uint256[], uint256[], uint256)
    : [
        normalizedCollection,
        tokenIds,
        pricesInWei,
        duration,
      ];  // ERC721: 4 params (address, uint256[], uint256[], uint256)

  const tx = await txManager.sendTransaction(
    exchangeContract,
    'batchListNFT',
    contractParams,
    { ...options, module: 'Exchange' }
  );

  const listingIds = this.extractListingIdsFromLogs(tx);
  return { listingIds, tx };
}
```

### Step 2: Add Amount Validation (Optional Enhancement)

Consider adding amount validation in the validation function:

```typescript
// Inside batchListNFT, after amounts normalization
if (tokenType === 'ERC1155') {
  for (let i = 0; i < normalizedAmounts.length; i++) {
    const amount = BigInt(normalizedAmounts[i]);
    if (amount <= 0) {
      throw this.error(
        ErrorCodes.INVALID_PARAMETER,
        `Amount at index ${i} must be greater than 0`
      );
    }
  }
}
```

## Key Insights

1. **Array Length Validation**: Must validate `amounts.length === tokenIds.length`
2. **Default Amounts**: Create array of '1's if amounts omitted for ERC1155
3. **Parameter Structure**: ERC1155 needs amounts array, ERC721 doesn't
4. **Error Messages**: Clear messages for array length mismatches
5. **Logging**: Add log statement for debugging

## Success Criteria

- [ ] ERC1155 batch listing works with explicit amounts
- [ ] ERC1155 batch listing works without amounts (defaults to ['1', '1', ...])
- [ ] ERC721 batch listing continues to work (backward compatible)
- [ ] Array length validation prevents invalid calls
- [ ] TypeScript compiles without errors

## Security Considerations

- Array length validation prevents out-of-bounds contract errors
- Amount > 0 validation prevents contract reverts
- Default amounts ['1', '1', ...] is safe for ERC1155
- Token detection via ERC165 (standard interface)

## Testing Strategy

**Test Cases:**
1. Batch list ERC721 without amounts (should work)
2. Batch list ERC1155 with amounts=['5', '10', '15'] (should work)
3. Batch list ERC1155 without amounts (should default to ['1', '1', '1'])
4. Batch list with mismatched array lengths (should fail validation)
5. Batch list with amount='0' (should fail validation)

**Expected Behavior:**
- ERC721: Always passes 4 params
- ERC1155: Always passes 5 params, amounts defaults to array of '1's

## Next Steps

Proceed to Phase 05: Update `formatListing()` to extract amount from contract data.

## References

- Debugger Report: Issue 2 (Batch listing missing amounts)
- ERC1155 Contract: `E:\zuno-marketplace-contracts\src\core\exchange\ERC1155NFTExchange.sol:75-81`
- ERC721 Contract: `E:\zuno-marketplace-contracts\src\core\exchange\ERC721NFTExchange.sol:73-78`
