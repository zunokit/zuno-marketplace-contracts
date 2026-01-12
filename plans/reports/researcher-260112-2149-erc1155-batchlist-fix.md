# Research Report: ERC1155 Batch List "invalid array value" Error

**Date:** 2026-01-12
**Issue:** #81 - Batch listing ERC1155 NFTs fails with "invalid array value"
**Repository:** zuno-marketplace-sdk
**Thoroughness:** Medium

---

## Executive Summary

Root cause identified: SDK's `ExchangeModule.batchListNFT()` missing required `amounts` parameter when calling ERC1155 exchange contract, causing parameter encoding mismatch during gas estimation.

**Impact:** Critical - blocks all ERC1155 batch listing operations

**Fix Complexity:** Low - requires adding amounts parameter to type definition and function call

---

## 1. Error Origin

**Location:** `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:588-593`

**Error Flow:**
1. `batchListNFT()` calls `txManager.sendTransaction()` with 4 parameters
2. TransactionManager calls `contractMethod.estimateGas()` at line 143
3. Ethers.js v6 attempts to encode parameters for ERC1155 contract
4. Parameter count mismatch → "invalid array value" error
5. Logged as "Gas estimation failed" with error data

**Code Location:**
```typescript
// Line 588-593 in ExchangeModule.ts
const tx = await txManager.sendTransaction(
  exchangeContract,
  'batchListNFT',
  [normalizedCollection, tokenIds, pricesInWei, duration],
  // ❌ Missing 'amounts' parameter for ERC1155
  { ...options, module: 'Exchange' }
);
```

---

## 2. Root Cause Analysis

### 2.1 Function Signature Mismatch

**ERC721 Exchange (working):**
```solidity
// src/core/exchange/ERC721NFTExchange.sol:73-77
function batchListNFT(
    address m_contractAddress,
    uint256[] calldata m_tokenIds,
    uint256[] calldata m_prices,
    uint256 m_listingDuration
) public
```
- **4 parameters** (contractAddress, tokenIds, prices, duration)
- ERC721 always has amount=1 per token

**ERC1155 Exchange (broken):**
```solidity
// src/core/exchange/ERC721NFTExchange.sol:75-81
function batchListNFT(
    address m_contractAddress,
    uint256[] memory m_tokenIds,
    uint256[] memory m_amounts,     // ← REQUIRED for ERC1155
    uint256[] memory m_prices,
    uint256 m_listingDuration
) public
```
- **5 parameters** (contractAddress, tokenIds, **amounts**, prices, duration)
- ERC1155 requires amounts array (same length as tokenIds)

**SDK Call (incorrect for ERC1155):**
```typescript
// src/modules/ExchangeModule.ts:591
[normalizedCollection, tokenIds, pricesInWei, duration]
// Sends 4 params to contract expecting 5
```

### 2.2 Parameter Encoding Details

**Ethers.js v6 Contract Encoding:**
- Uses contract ABI to validate parameter count/types
- When calling `batchListNFT` on ERC1155 contract with 4 params:
  - Expects: `(address, uint256[], uint256[], uint256[], uint256)`
  - Receives: `(address, uint256[], uint256[], uint256)`
  - Error: "invalid array value" - 3rd array parameter interpreted as wrong type

**Why error happens at gas estimation:**
```typescript
// src/utils/transactions.ts:143
const estimatedGas = await contractMethod.estimateGas(...args, overrides);
```
- `estimateGas()` attempts to encode transaction data
- Encoding fails due to parameter mismatch
- Caught at line 146-152, logged as "Gas estimation failed"

---

## 3. Type Definition Gap

**Current Type (src/types/contracts.ts:98-104):**
```typescript
export interface BatchListNFTParams {
  collectionAddress: string;
  tokenIds: string[];
  prices: string[];
  duration: number;
  options?: TransactionOptions;
  // ❌ Missing: amounts?: number[];
}
```

**Expected Type:**
```typescript
export interface BatchListNFTParams {
  collectionAddress: string;
  tokenIds: string[];
  amounts?: number[];     // ← Required for ERC1155, optional for ERC721
  prices: string[];
  duration: number;
  options?: TransactionOptions;
}
```

**Note:** AuctionModule batch types already include `amounts?: number[]` for ERC1155 support (lines 254, 285).

---

## 4. Contract Interface Status

**IERC721NFTExchange.sol** (lines 11-16):
```solidity
function batchListNFT(
    address contractAddress,
    uint256[] memory tokenIds,
    uint256[] memory prices,
    uint256 listingDuration
) external;
```
✅ Interface defined and matches implementation

**IERC1155NFTExchange.sol**:
```solidity
// ❌ batchListNFT NOT defined in interface
// Only listNFT, buyListedNFT, cancelListing, updateListingPrice, getListing
```
⚠️ Interface incomplete - batchListNFT missing from interface but exists in implementation

---

## 5. Affected Code Paths

**Primary:**
- `ExchangeModule.batchListNFT()` (line 561-597)
- Called when user batches ERC1155 NFTs from same collection

**Secondary:**
- Type validation passes (amounts not required)
- Approval flow works
- Only contract call fails

**Not Affected:**
- Single NFT listing (`listNFT`) - different code path (line 132-169)
- ERC721 batch listing - 4 parameters match contract expectation
- Batch buy/cancel operations - different functions

---

## 6. Expected vs Actual Parameter Format

### ERC721 Batch List (Working)
```
Expected: (address, uint256[], uint256[], uint256)
Actual:   (address, uint256[], uint256[], uint256)
Status:   ✅ Match
```

### ERC1155 Batch List (Broken)
```
Expected: (address, uint256[], uint256[], uint256[], uint256)
Actual:   (address, uint256[], uint256[], uint256)
Status:   ❌ Missing 3rd parameter (amounts)
```

**Parameter mapping:**
| Position | ERC721 Expects | ERC1155 Expects | SDK Sends |
|----------|---------------|-----------------|-----------|
| 0        | address       | address         | address   |
| 1        | uint256[]     | uint256[]       | uint256[] |
| 2        | uint256[] (prices) | uint256[] (amounts) | uint256[] (prices) ❌ |
| 3        | uint256 (duration) | uint256[] (prices) | uint256 (duration) ❌ |
| 4        | N/A           | uint256 (duration) | N/A       |

---

## 7. Proposed Fix Approach

### 7.1 Update Type Definition

**File:** `src/types/contracts.ts`

```typescript
export interface BatchListNFTParams {
  collectionAddress: string;
  tokenIds: string[];
  amounts?: number[];     // ← Add optional amounts array
  prices: string[];
  duration: number;
  options?: TransactionOptions;
}
```

### 7.2 Update batchListNFT Implementation

**File:** `src/modules/ExchangeModule.ts`

**Changes needed:**
1. Extract `amounts` from params (line 562)
2. Default amounts to array of 1s for ERC721 (line 586-587)
3. Conditionally include amounts in contract call (line 591)

**Pseudo-code:**
```typescript
async batchListNFT(params: BatchListNFTParams) {
  const { collectionAddress, tokenIds, amounts, prices, duration, options } = params;

  // Detect token standard (already done at line 580)
  const isERC1155 = tokenType === 'ERC1155';

  // Prepare amounts array
  const amountsArray = amounts || (isERC1155
    ? tokenIds.map(() => 1)  // Default to 1 for ERC1155 if not provided
    : undefined              // Don't send for ERC721
  );

  // Build parameters based on token type
  const contractArgs = isERC1155
    ? [normalizedCollection, tokenIds, amountsArray, pricesInWei, duration]
    : [normalizedCollection, tokenIds, pricesInWei, duration];

  const tx = await txManager.sendTransaction(
    exchangeContract,
    'batchListNFT',
    contractArgs,
    { ...options, module: 'Exchange' }
  );
}
```

### 7.3 Validation Updates

Add validation in `batchListNFT`:
```typescript
// For ERC1155, validate amounts array
if (isERC1155 && (!amounts || amounts.length !== tokenIds.length)) {
  throw this.error(ErrorCodes.INVALID_PARAMETER,
    'Amounts array required for ERC1155 and must match tokenIds length');
}
```

---

## 8. Test Cases Required

### 8.1 ERC1155 Batch List
```typescript
// Should pass with amounts
await sdk.exchange.batchListNFT({
  collectionAddress: '0x...',
  tokenIds: ['1', '2', '3'],
  amounts: [5, 10, 2],  // ← Required for ERC1155
  prices: ['1.0', '2.0', '0.5'],
  duration: 86400,
});
```

### 8.2 ERC721 Batch List
```typescript
// Should pass without amounts (defaults to 1s)
await sdk.exchange.batchListNFT({
  collectionAddress: '0x...',
  tokenIds: ['1', '2', '3'],
  prices: ['1.0', '2.0', '0.5'],
  duration: 86400,
  // amounts: optional - defaults to [1, 1, 1]
});
```

### 8.3 Error Cases
```typescript
// ERC1155 without amounts → error
// ERC1155 amounts.length !== tokenIds.length → error
// amounts.length === 0 → error
```

---

## 9. Breaking Changes

**None** - Adding optional `amounts` parameter is backward compatible:
- Existing ERC721 calls work unchanged
- ERC1155 calls currently broken, will work after fix
- No API changes required for consumers

---

## 10. Related Issues

**Contract Interface Gap:**
- `IERC1155NFTExchange.sol` missing `batchListNFT` function signature
- Should be added for completeness (not critical for SDK fix)

**Similar Pattern in AuctionModule:**
- Batch auction types already support `amounts?: number[]`
- Can reference `BatchCreateEnglishAuctionParams` (line 254) for pattern

---

## 11. Unresolved Questions

1. **Default amounts behavior:** Should SDK default ERC1155 amounts to [1,1,1...] if not provided, or require explicit amounts?
   - **Recommendation:** Require explicit amounts for ERC1155 to prevent errors

2. **Interface file sync:** Should `IERC1155NFTExchange.sol` be updated to include `batchListNFT`?
   - **Recommendation:** Yes, for API completeness and documentation

3. **Amounts validation:** Should SDK validate amounts values (e.g., > 0)?
   - **Recommendation:** Yes, add validation for `amount > 0` for each element

4. **Gas estimation behavior:** Why does ethers.js throw "invalid array value" instead of "missing argument"?
   - **Answer:** Encoding error - parameter type mismatch interpreted as invalid value

---

## 12. Implementation Priority

**HIGH PRIORITY** - Blocks all ERC1155 batch listing operations

**Estimated Fix Time:** 1-2 hours
- Type definition: 5 min
- Function logic: 30 min
- Validation: 15 min
- Testing: 30-45 min

**Risk Level:** Low
- Isolated change
- No breaking changes
- Easy to test

---

## 13. References

**Contract Files:**
- `E:\zuno-marketplace-contracts\src\core\exchange\ERC1155NFTExchange.sol:75-110`
- `E:\zuno-marketplace-contracts\src\core\exchange\ERC721NFTExchange.sol:73-105`
- `E:\zuno-marketplace-contracts\src\interfaces\core\IERC1155NFTExchange.sol`

**SDK Files:**
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:561-597`
- `E:\zuno-marketplace-sdk\src\types\contracts.ts:98-104`
- `E:\zuno-marketplace-sdk\src\utils\transactions.ts:143`

**Ethers.js Documentation:**
- Contract encoding: https://docs.ethers.org/v6/api/contract/#Contract
- Error types: https://docs.ethers.org/v6/api/errors/

---

## Appendix A: Contract Function Signatures

**ERC721.batchListNFT:**
```solidity
function batchListNFT(
    address m_contractAddress,
    uint256[] calldata m_tokenIds,
    uint256[] calldata m_prices,
    uint256 m_listingDuration
) public
```

**ERC1155.batchListNFT:**
```solidity
function batchListNFT(
    address m_contractAddress,
    uint256[] memory m_tokenIds,
    uint256[] memory m_amounts,
    uint256[] memory m_prices,
    uint256 m_listingDuration
) public
```

**Key Difference:** ERC1155 requires `amounts` array (parameter index 2)

---

**End of Report**
