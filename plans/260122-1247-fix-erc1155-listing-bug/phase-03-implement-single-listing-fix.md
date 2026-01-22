---
title: "Phase 03: Implement Single Listing Fix"
description: "Update listNFT() to detect token type and pass correct parameters"
status: pending
priority: P1
effort: 1.5h
tags: [implementation, listNFT, erc1155]
---

## Overview

Update `listNFT()` function to detect ERC721 vs ERC1155 and pass correct parameter array (4 params for ERC721, 5 params for ERC1155 including amount).

## Requirements

### Functional Requirements
1. Detect token standard before listing
2. Pass 4 params to ERC721 contract
3. Pass 5 params to ERC1155 contract (including amount)
4. Default amount to '1' for ERC1155 if omitted
5. Validate amount > 0 for ERC1155
6. Maintain backward compatibility for ERC721

### Non-Functional Requirements
- Minimal performance impact
- Clear error messages
- TypeScript type safety

## Related Code Files

### Files to Modify

**`E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts`**
- Lines 132-169: `listNFT()` function

### Dependencies

- `ContractRegistry.verifyTokenStandard()` - Already implemented
- `getExchangeContract()` - Already uses token detection

## Implementation Steps

### Step 1: Import TokenStandard Type

**Location:** Top of ExchangeModule.ts (line ~7-14)

```typescript
import type {
  ListNFTParams,
  BatchListNFTParams,
  BuyNFTParams,
  BatchBuyNFTParams,
  BatchCancelListingParams,
  TransactionOptions,
  TokenStandard,  // <-- ADD THIS
} from '../types/contracts';
```

### Step 2: Update listNFT() Function

**File:** `src/modules/ExchangeModule.ts:132-169`

**Current Code:**
```typescript
async listNFT(params: ListNFTParams): Promise<{ listingId: string; tx: TransactionReceipt }> {
  validateListNFTParams(params);

  const { collectionAddress, tokenId, price, duration, options } = params;
  const txManager = this.ensureTxManager();
  const provider = this.ensureProvider();
  const sellerAddress = this.signer ? await this.signer.getAddress() : ethers.ZeroAddress;

  await this.ensureApproval(collectionAddress, sellerAddress);

  const exchangeContract = await this.getExchangeContract(
    collectionAddress,
    provider,
    this.signer
  );

  const priceInWei = ethers.parseEther(price);

  const tx = await txManager.sendTransaction(
    exchangeContract,
    'listNFT',
    [collectionAddress, tokenId, priceInWei, duration],  // <-- ALWAYS 4 PARAMS
    { ...options, module: 'Exchange' }
  );

  const listingId = await this.extractListingId(tx);
  return { listingId, tx };
}
```

**Updated Code:**
```typescript
async listNFT(params: ListNFTParams): Promise<{ listingId: string; tx: TransactionReceipt }> {
  validateListNFTParams(params);

  const { collectionAddress, tokenId, price, duration, amount, options } = params;
  const txManager = this.ensureTxManager();
  const provider = this.ensureProvider();
  const sellerAddress = this.signer ? await this.signer.getAddress() : ethers.ZeroAddress;

  await this.ensureApproval(collectionAddress, sellerAddress);

  // Detect token standard to determine correct parameters
  const tokenType: TokenStandard = await this.contractRegistry.verifyTokenStandard(
    collectionAddress,
    provider
  );

  this.log('Detected token type for listing', { collectionAddress, tokenType });

  const exchangeContract = await this.getExchangeContract(
    collectionAddress,
    provider,
    this.signer
  );

  const priceInWei = ethers.parseEther(price);

  // Prepare parameters based on token type
  const contractParams = tokenType === 'ERC1155'
    ? [
        collectionAddress,
        tokenId,
        amount || '1',  // Default to 1 for ERC1155 if not specified
        priceInWei,
        duration,
      ]  // ERC1155: 5 params (address, uint256, uint256, uint256, uint256)
    : [
        collectionAddress,
        tokenId,
        priceInWei,
        duration,
      ];  // ERC721: 4 params (address, uint256, uint256, uint256)

  const tx = await txManager.sendTransaction(
    exchangeContract,
    'listNFT',
    contractParams,
    { ...options, module: 'Exchange' }
  );

  const listingId = await this.extractListingId(tx);
  return { listingId, tx };
}
```

### Step 3: Add Validation (Optional Enhancement)

Consider adding validation in `validateListNFTParams()` in `src/utils/errors.ts`:

```typescript
export function validateListNFTParams(params: ListNFTParams): void {
  // ... existing validation ...

  // Validate amount if provided
  if (params.amount !== undefined) {
    const amount = BigInt(params.amount);
    if (amount <= 0) {
      throw new ZunoSDKError(
        ErrorCodes.INVALID_PARAMETER,
        'Amount must be greater than 0'
      );
    }
  }
}
```

## Key Insights

1. **Token Detection**: Use existing `verifyTokenStandard()` - already tested and working
2. **Parameter Structure**: ERC1155 needs 5 params, ERC721 needs 4 params
3. **Default Amount**: Default to '1' for ERC1155 if user omits amount
4. **Backward Compatible**: ERC721 code path unchanged (4 params)
5. **Logging**: Add log statement for debugging token type detection

## Success Criteria

- [ ] ERC1155 listing works with explicit amount
- [ ] ERC1155 listing works without amount (defaults to '1')
- [ ] ERC721 listing continues to work (backward compatible)
- [ ] TypeScript compiles without errors
- [ ] Contract calls match expected signatures

## Security Considerations

- Amount > 0 validation prevents contract reverts
- Token detection via ERC165 (standard interface)
- Default amount '1' is safe for ERC1155
- No user input directly passed to contract without validation

## Testing Strategy

**Test Cases:**
1. List ERC721 without amount (should work)
2. List ERC1155 with amount='10' (should work)
3. List ERC1155 without amount (should default to '1')
4. List with amount='0' (should fail validation)

**Expected Behavior:**
- ERC721: Always passes 4 params
- ERC1155: Always passes 5 params, amount defaults to '1'

## Next Steps

Proceed to Phase 04: Implement batch listing fix in `batchListNFT()`.

## References

- Debugger Report: Issue 1 (Single listing missing amount)
- ERC1155 Contract: `E:\zuno-marketplace-contracts\src\core\exchange\ERC1155NFTExchange.sol:41-47`
- ERC721 Contract: `E:\zuno-marketplace-contracts\src\core\exchange\ERC721NFTExchange.sol:40`
