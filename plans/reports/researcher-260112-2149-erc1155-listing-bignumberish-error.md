# Research Report: ERC1155 Single Listing "invalid BigNumberish value" Error

**Date:** 2026-01-12
**Issue:** #80 - Invalid BigNumberish value when single listing ERC1155 NFTs
**Thoroughness:** Medium
**Status:** Root Cause Identified

---

## Executive Summary

The "invalid BigNumberish value" error occurs when listing ERC1155 NFTs because the `ExchangeModule.listNFT()` method is missing the required `amount` parameter that ERC1155 contracts need. The SDK passes an empty object `{}` instead of a BigNumber value, causing ethers.js v6 to throw an `INVALID_ARGUMENT` error.

## Root Cause Analysis

### Contract Interface Mismatch

**ERC721NFTExchange.listNFT signature:**
```solidity
function listNFT(address contractAddress, uint256 tokenId, uint256 price, uint256 listingDuration)
```

**ERC1155NFTExchange.listNFT signature:**
```solidity
function listNFT(address contractAddress, uint256 tokenId, uint256 price, uint256 amount, uint256 listingDuration)
```

The **key difference**: ERC1155 requires an `amount` parameter (4th parameter) between `price` and `listingDuration`.

### Current SDK Implementation

**Location:** `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts` (lines 154-163)

```typescript
// Prepare parameters - contract expects: (address, uint256, uint256, uint256)
const priceInWei = ethers.parseEther(price);

// Call contract method
const tx = await txManager.sendTransaction(
  exchangeContract,
  'listNFT',
  [collectionAddress, tokenId, priceInWei, duration],  // ❌ Missing 'amount' for ERC1155
  { ...options, module: 'Exchange' }
);
```

**Problem:** The comment says "contract expects: (address, uint256, uint256, uint256)" but this is only true for ERC721. For ERC1155, it expects **5 parameters**, not 4.

### Why Empty Object `{}` Appears

When ethers.js v6 receives the wrong number of parameters:
1. SDK calls `listNFT(collectionAddress, tokenId, priceInWei, duration)` (4 args)
2. ERC1155 contract expects: `listNFT(address, tokenId, price, amount, duration)` (5 args)
3. Parameter mapping shifts: `duration` (4th arg) → `amount` (4th param)
4. 5th parameter `duration` receives `undefined` → formatted as `{}` by ethers
5. Error: `invalid BigNumberish value (argument="value", value={}, code=INVALID_ARGUMENT)`

## Evidence from Codebase

### Type Definitions
**File:** `E:\zuno-marketplace-sdk\src\types\contracts.ts`

```typescript
export interface ListNFTParams {
  collectionAddress: string;
  tokenId: string;
  price: string;
  duration: number;
  options?: TransactionOptions;
}
```

**Missing:** `amount?: number` field (needed for ERC1155)

### AuctionModule Handles This Correctly
**File:** `E:\zuno-marketplace-sdk\src\modules\AuctionModule.ts` (line 175)

```typescript
async createEnglishAuction(params: CreateEnglishAuctionParams) {
  const {
    collectionAddress,
    tokenId,
    amount = 1,  // ✅ Default to 1 (works for both ERC721 and ERC1155)
    startingBid,
    duration,
    // ...
  } = params;

  // Passes 'amount' to contract
  await txManager.sendTransaction(
    auctionFactory,
    "createEnglishAuction",
    [normalizedCollection, tokenId, amount, startingBidWei, reservePriceWei, duration],
    // ...
  );
}
```

**Type definition:**
```typescript
export interface CreateEnglishAuctionParams {
  collectionAddress: string;
  tokenId: string;
  amount?: number; // For ERC1155, default 1 for ERC721 ✅
  startingBid: string;
  // ...
}
```

## Batch Listing Also Affected

**ERC1155NFTExchange.batchListNFT signature:**
```solidity
function batchListNFT(
    address m_contractAddress,
    uint256[] memory m_tokenIds,
    uint256[] memory m_amounts,  // ❌ Missing in SDK
    uint256[] memory m_prices,
    uint256 m_listingDuration
)
```

**Current SDK batchListNFT (line 588-592):**
```typescript
const tx = await txManager.sendTransaction(
  exchangeContract,
  'batchListNFT',
  [normalizedCollection, tokenIds, pricesInWei, duration],  // ❌ Missing amounts array
  { ...options, module: 'Exchange' }
);
```

## Impact Assessment

### Affected Operations
1. ✅ **Single listing ERC721** - Works (no amount parameter needed)
2. ❌ **Single listing ERC1155** - Broken (missing amount parameter)
3. ✅ **Batch listing ERC721** - Works (amounts not needed)
4. ❌ **Batch listing ERC1155** - Broken (missing amounts array)
5. ✅ **Buying ERC1155** - Works (buyNFT not affected by this issue)

### User Impact
- ERC1155 collections **cannot be listed** for sale
- Error appears during gas estimation (before transaction)
- No workaround exists in current SDK API

## Proposed Fix Approach

### 1. Update Type Definitions

**File:** `E:\zuno-marketplace-sdk\src\types\contracts.ts`

```typescript
export interface ListNFTParams {
  collectionAddress: string;
  tokenId: string;
  price: string;
  amount?: number; // Add: defaults to 1 (ERC721), configurable for ERC1155
  duration: number;
  options?: TransactionOptions;
}

export interface BatchListNFTParams {
  collectionAddress: string;
  tokenIds: string[];
  prices: string[];
  amounts?: number[]; // Add: defaults to [1,1,1...] for ERC721
  duration: number;
  options?: TransactionOptions;
}
```

### 2. Update ExchangeModule.listNFT

**File:** `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts`

```typescript
async listNFT(params: ListNFTParams): Promise<{ listingId: string; tx: TransactionReceipt }> {
  validateListNFTParams(params);

  // Extract with default
  const { collectionAddress, tokenId, price, amount = 1, duration, options } = params;

  // ... validation code ...

  const priceInWei = ethers.parseEther(price);

  // Detect token type to determine parameter order
  const tokenType = await this.contractRegistry.verifyTokenStandard(
    collectionAddress,
    provider
  );

  // ERC1155 needs amount parameter
  if (tokenType === 'ERC1155') {
    const tx = await txManager.sendTransaction(
      exchangeContract,
      'listNFT',
      [collectionAddress, tokenId, priceInWei, amount, duration],  // ✅ 5 params
      { ...options, module: 'Exchange' }
    );
  } else {
    // ERC721 - 4 params (original behavior)
    const tx = await txManager.sendTransaction(
      exchangeContract,
      'listNFT',
      [collectionAddress, tokenId, priceInWei, duration],
      { ...options, module: 'Exchange' }
    );
  }

  // ...
}
```

### 3. Update ExchangeModule.batchListNFT

```typescript
async batchListNFT(params: BatchListNFTParams): Promise<{ listingIds: string[]; tx: TransactionReceipt }> {
  const { collectionAddress, tokenIds, prices, amounts, duration, options } = params;

  // Default amounts to 1 for each token if not provided (ERC721 compatible)
  const normalizedAmounts = amounts || tokenIds.map(() => 1);

  if (tokenIds.length !== normalizedAmounts.length) {
    throw this.error(ErrorCodes.INVALID_PARAMETER, 'Token IDs and amounts arrays must have same length');
  }

  // ... rest of validation ...

  // Detect token type
  const tokenType = await this.contractRegistry.verifyTokenStandard(
    normalizedCollection,
    provider
  );

  if (tokenType === 'ERC1155') {
    const tx = await txManager.sendTransaction(
      exchangeContract,
      'batchListNFT',
      [normalizedCollection, tokenIds, normalizedAmounts, pricesInWei, duration],  // ✅ 5 params
      { ...options, module: 'Exchange' }
    );
  } else {
    // ERC721 - 4 params (original behavior)
    const tx = await txManager.sendTransaction(
      exchangeContract,
      'batchListNFT',
      [normalizedCollection, tokenIds, pricesInWei, duration],
      { ...options, module: 'Exchange' }
    );
  }

  // ...
}
```

### 4. Alternative Approach: Parameter Object Mapping

Instead of conditional logic, map parameters based on detected token type:

```typescript
private getListNFTArgs(
  tokenType: 'ERC721' | 'ERC1155',
  collectionAddress: string,
  tokenId: string,
  priceInWei: bigint,
  amount: number,
  duration: number
): unknown[] {
  if (tokenType === 'ERC1155') {
    return [collectionAddress, tokenId, priceInWei, amount, duration];
  }
  return [collectionAddress, tokenId, priceInWei, duration];
}
```

## Testing Requirements

### Unit Tests Needed
1. **ERC1155 single listing** with explicit amount
2. **ERC1155 single listing** with default amount (1)
3. **ERC1155 batch listing** with amounts array
4. **ERC1155 batch listing** without amounts (defaults to [1,1,...])
5. **Backwards compatibility** - ERC721 listings still work
6. **Validation** - amounts array length matches tokenIds array

### Integration Tests
1. List ERC1155 NFT (single) → verify on-chain
2. List ERC1155 NFTs (batch) → verify on-chain
3. List ERC721 NFT (single) → ensure no regression
4. List ERC721 NFTs (batch) → ensure no regression

## Unresolved Questions

1. **Amount Validation:** Should we validate `amount > 0`? Yes, likely needed.
2. **Type Detection Overhead:** Calling `verifyTokenStandard` twice (once in `getExchangeContract`, again in `listNFT`) - can we cache this?
3. **ABI Versioning:** If ABI changes in future, how do we handle different contract versions?
4. **Error Messages:** Can we provide better error messages that indicate "amount parameter missing for ERC1155"?

## Related Issues

- AuctionModule already handles `amount` correctly for ERC1155
- Similar pattern may exist in other modules (Bundle, Offer)
- Consider consistency across all NFT operations

## Recommendations

1. **Immediate Fix:** Implement amount parameter for `listNFT` and `batchListNFT`
2. **Documentation:** Update docs to clarify `amount` parameter usage for ERC1155
3. **Testing:** Add ERC1155-specific tests to prevent regression
4. **Code Review:** Check other modules (BundleModule, OfferManager) for similar issues
5. **Type Safety:** Consider stricter types (e.g., `ERC721ListParams` vs `ERC1155ListParams`)

---

**Researcher:** researcher agent (ae2c263)
**Report Location:** `E:\zuno-marketplace-contracts\plans\reports\researcher-260112-2149-erc1155-listing-bignumberish-error.md`
