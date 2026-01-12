# Allowlist State Management Bug - Research Report

**Date:** 2026-01-12
**Issue:** #85 - Allowlist State Inconsistency
**Researcher:** Claude (Researcher Agent)
**Thoroughness:** Medium

---

## Executive Summary

Root cause identified: **No bug found in contracts or SDK**. The issue stems from **frontend React Query cache invalidation mismatch**.

The allowlist functions work correctly at the contract and SDK level. The problem is that React Query hooks cache stale allowlist data because:
1. `useIsInAllowlist` uses query key `['allowlist', collectionAddress, userAddress]`
2. `useIsAllowlistOnly` uses query key `['allowlistOnly', collectionAddress]`
3. Allowlist mutations invalidate `['collection', collectionAddress]` - **different keys**

This causes the frontend to show outdated allowlist status after add/remove operations.

---

## 1. Contract Analysis (zuno-marketplace-contracts)

### 1.1 Allowlist Functions (BaseCollection.sol)

**Location:** `E:\zuno-marketplace-contracts\src\common\BaseCollection.sol`

#### addToAllowlist (Lines 56-67)
```solidity
function addToAllowlist(address[] calldata addresses) external onlyOwner {
    uint256 length = addresses.length;
    if (length == 0) revert Collection__InvalidAmount();
    if (length > MAX_ALLOWLIST_BATCH_SIZE) {
        revert Collection__MintLimitExceeded();
    }

    for (uint256 i = 0; i < length; i++) {
        if (addresses[i] == address(0)) revert Collection__InvalidAmount();
        s_allowlist[addresses[i]] = true;  // ✅ Sets mapping to true
    }
}
```

#### removeFromAllowlist (Lines 73-83)
```solidity
function removeFromAllowlist(address[] calldata addresses) external onlyOwner {
    uint256 length = addresses.length;
    if (length == 0) revert Collection__InvalidAmount();
    if (length > MAX_ALLOWLIST_BATCH_SIZE) {
        revert Collection__MintLimitExceeded();
    }

    for (uint256 i = 0; i < length; i++) {
        s_allowlist[addresses[i]] = false;  // ✅ Sets mapping to false
    }
}
```

#### setAllowlistOnly (Lines 89-91)
```solidity
function setAllowlistOnly(bool allowlistOnly) external onlyOwner {
    s_allowlistOnly = allowlistOnly;  // ✅ Updates boolean
}
```

**Verdict:** ✅ Contract functions are **correct** - they properly update state.

### 1.2 Allowlist Check in Mint (Lines 161-189)

```solidity
function _validateMintConditions(address to, uint256 amount) internal {
    // Auto-update stage based on current time
    MintStage currentStage = _calculateCurrentStage();
    if (currentStage != s_currentStage) {
        s_currentStage = currentStage;
        emit StageUpdated(s_currentStage, block.timestamp);
    }

    // ... (other checks)

    // Check allowlist if in allowlist stage
    if (s_currentStage == MintStage.ALLOWLIST) {
        if (!s_allowlist[to]) revert Collection__NotInAllowlist();  // ✅ Correct check
    }
}
```

**Stage Calculation (Lines 137-146):**
```solidity
function _calculateCurrentStage() internal view returns (MintStage) {
    if (block.timestamp < s_mintStartTime) {
        return MintStage.INACTIVE;
    } else if (block.timestamp < s_allowlistStageEnd || s_allowlistOnly) {
        // If allowlistOnly is true, never go to PUBLIC stage
        return MintStage.ALLOWLIST;
    } else {
        return MintStage.PUBLIC;
    }
}
```

**Verdict:** ✅ Mint logic is **correct** - it checks `s_allowlist[to]` mapping directly.

---

## 2. SDK Analysis (zuno-marketplace-sdk)

### 2.1 CollectionModule.ts Allowlist Functions

**Location:** `E:\zuno-marketplace-sdk\src\modules\CollectionModule.ts`

#### addToAllowlist (Lines 746-766)
```typescript
async addToAllowlist(
  collectionAddress: string,
  addresses: string[]
): Promise<{ tx: TransactionReceipt }> {
  // ... validation ...
  const abi = ['function addToAllowlist(address[] calldata addresses) external'];
  const contract = new ethers.Contract(normalizedCollection, abi, this.signer);
  const tx = await txManager.sendTransaction(contract, 'addToAllowlist', [addresses], ...);
  return { tx };
}
```

#### removeFromAllowlist (Lines 794-814)
```typescript
async removeFromAllowlist(
  collectionAddress: string,
  addresses: string[]
): Promise<{ tx: TransactionReceipt }> {
  // ... validation ...
  const abi = ['function removeFromAllowlist(address[] calldata addresses) external'];
  const contract = new ethers.Contract(normalizedCollection, abi, this.signer);
  const tx = await txManager.sendTransaction(contract, 'removeFromAllowlist', [addresses], ...);
  return { tx };
}
```

#### setAllowlistOnly (Lines 840-859)
```typescript
async setAllowlistOnly(
  collectionAddress: string,
  enabled: boolean
): Promise<{ tx: TransactionReceipt }> {
  // ... validation ...
  const abi = ['function setAllowlistOnly(bool allowlistOnly) external'];
  const contract = new ethers.Contract(normalizedCollection, abi, this.signer);
  const tx = await txManager.sendTransaction(contract, 'setAllowlistOnly', [enabled], ...);
  return { tx };
}
```

#### isInAllowlist (Lines 882-894)
```typescript
async isInAllowlist(collectionAddress: string, address: string): Promise<boolean> {
  const abi = ['function isInAllowlist(address account) external view returns (bool)'];
  const contract = new ethers.Contract(normalizedCollection, abi, provider);
  return await contract.isInAllowlist(normalizedAddress);  // ✅ Live contract call
}
```

#### isAllowlistOnly (Lines 915-926)
```typescript
async isAllowlistOnly(collectionAddress: string): Promise<boolean> {
  const abi = ['function isAllowlistOnly() external view returns (bool)'];
  const contract = new ethers.Contract(normalizedCollection, abi, provider);
  return await contract.isAllowlistOnly();  // ✅ Live contract call
}
```

**Verdict:** ✅ SDK functions are **correct** - they directly call contract functions.

---

## 3. React Hooks Analysis (Root Cause)

**Location:** `E:\zuno-marketplace-sdk\src\react\hooks\useCollection.ts`

### 3.1 Query Keys Mismatch

#### Allowlist Query Hooks
```typescript
// Line 166-174: useIsInAllowlist
export function useIsInAllowlist(collectionAddress?: string, userAddress?: string) {
  return useQuery({
    queryKey: ['allowlist', collectionAddress, userAddress],  // ❌ Key: ['allowlist', ...]
    queryFn: () => sdk.collection.isInAllowlist(collectionAddress!, userAddress!),
    enabled: !!collectionAddress && !!userAddress,
  });
}

// Line 179-187: useIsAllowlistOnly
export function useIsAllowlistOnly(collectionAddress?: string) {
  return useQuery({
    queryKey: ['allowlistOnly', collectionAddress],  // ❌ Key: ['allowlistOnly', ...]
    queryFn: () => sdk.collection.isAllowlistOnly(collectionAddress!),
    enabled: !!collectionAddress,
  });
}
```

#### Mutation Hooks (Wrong Invalidation Keys)
```typescript
// Line 76-82: addToAllowlist mutation
const addToAllowlist = useMutation({
  mutationFn: ({ collectionAddress, addresses }) =>
    sdk.collection.addToAllowlist(collectionAddress, addresses),
  onSuccess: (_, variables) => {
    queryClient.invalidateQueries({
      queryKey: ['collection', variables.collectionAddress]  // ❌ Wrong! Should be ['allowlist', ...]
    });
  },
});

// Line 84-90: removeFromAllowlist mutation
const removeFromAllowlist = useMutation({
  mutationFn: ({ collectionAddress, addresses }) =>
    sdk.collection.removeFromAllowlist(collectionAddress, addresses),
  onSuccess: (_, variables) => {
    queryClient.invalidateQueries({
      queryKey: ['collection', variables.collectionAddress]  // ❌ Wrong! Should be ['allowlist', ...]
    });
  },
});

// Line 92-98: setAllowlistOnly mutation
const setAllowlistOnly = useMutation({
  mutationFn: ({ collectionAddress, enabled }) =>
    sdk.collection.setAllowlistOnly(collectionAddress, enabled),
  onSuccess: (_, variables) => {
    queryClient.invalidateQueries({
      queryKey: ['collection', variables.collectionAddress]  // ❌ Wrong! Should be ['allowlistOnly', ...]
    });
  },
});
```

### 3.2 The Bug

When user adds address to allowlist:
1. ✅ Contract updates `s_allowlist[user] = true`
2. ✅ Transaction succeeds
3. ❌ Mutation invalidates `['collection', address]`
4. ❌ `useIsInAllowlist` uses key `['allowlist', address, user]` - **NOT invalidated**
5. ❌ Frontend shows stale cached value (false) instead of true

Result: User sees "not allowlisted" even though they are.

---

## 4. Frontend Usage (zuno-marketplace-mini)

**Location:** `E:\zuno-marketplace-mini\src\app\mint\[id]\page.tsx`

```typescript
// Line 61-62
const { data: isInAllowlist } = useIsInAllowlist(collectionAddress, address);
const { data: isAllowlistOnly } = useIsAllowlistOnly(collectionAddress);

// Line 97-103: Client-side check (bypassed by contract anyway)
const handleMint = async () => {
  // Check allowlist if collection is in allowlist-only mode
  if (isAllowlistOnly && !isInAllowlist) {
    toast.error("You are not in the allowlist", { ... });
    return;  // ❌ Blocks mint due to stale cache
  }
  // ... mint call ...
};
```

**Note:** The client-side check at line 97 is redundant since the contract enforces allowlist anyway. However, this is where users see the error due to stale cache.

---

## 5. Data Flow Map

```
┌─────────────────────────────────────────────────────────────────┐
│                      ALLOWLIST OPERATION                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User clicks "Add to Allowlist"                              │
│     └─> addToAllowlist.mutateAsync()                           │
│                                                                  │
│  2. SDK calls contract                                          │
│     └─> contract.addToAllowlist(addresses)                      │
│         └─> s_allowlist[addr] = true ✅                         │
│                                                                  │
│  3. Transaction succeeds                                        │
│     └─> onSuccess callback fires                                │
│         └─> invalidateQueries(['collection', addr]) ❌          │
│             (WRONG KEY - doesn't match allowlist hooks)         │
│                                                                  │
│  4. React Query cache                                          │
│     └─> ['allowlist', collection, user] still has old data ❌  │
│     └─> useIsInAllowlist returns stale value                   │
│                                                                  │
│  5. Frontend displays                                           │
│     └─> Shows "not in allowlist" (stale cache)                 │
│     └─> Blocks mint button (if client check enabled)           │
│                                                                  │
│  6. User tries to mint                                          │
│     └─> Frontend blocks (stale data) OR                        │
│     └─> Contract allows (correct state)                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Issue Breakdown

### Issue #1: Adding address doesn't allow minting
**Cause:** React Query cache not invalidated after `addToAllowlist`
- Query key: `['allowlist', collection, user]`
- Invalidates: `['collection', collection]` (wrong)
- Result: Stale `false` value

### Issue #2: Removing only address doesn't clear state
**Cause:** Same cache invalidation mismatch
- Contract correctly sets `s_allowlist[addr] = false`
- Frontend still shows `true` (stale cache)

### Issue #3: Disabling allowlist allows owner but users get error
**Cause:** Multiple problems:
1. Cache invalidation mismatch for `setAllowlistOnly`
2. Client-side check blocks mint even when contract would allow
3. If `isAllowlistOnly` is stale (still true), blocks incorrectly

---

## 7. Component-Level Issue Distribution

| Component | Has Bug? | Type | Severity |
|-----------|----------|------|----------|
| **Contracts** | ❌ No | None | N/A |
| **SDK** | ❌ No | None | N/A |
| **React Hooks** | ✅ Yes | Cache invalidation mismatch | **HIGH** |
| **Frontend** | ⚠️ Minor | Redundant client-side check | LOW |

**Primary Bug Location:** `src/react/hooks/useCollection.ts` lines 76-98

---

## 8. Proposed Fix Approach

### Option 1: Fix Query Keys (Recommended)

**File:** `src/react/hooks/useCollection.ts`

```typescript
// Fix addToAllowlist invalidation
const addToAllowlist = useMutation({
  mutationFn: ({ collectionAddress, addresses }) =>
    sdk.collection.addToAllowlist(collectionAddress, addresses),
  onSuccess: (_, variables) => {
    // ✅ Invalidate allowlist queries
    queryClient.invalidateQueries({
      queryKey: ['allowlist', variables.collectionAddress]
    });
  },
});

// Fix removeFromAllowlist invalidation
const removeFromAllowlist = useMutation({
  mutationFn: ({ collectionAddress, addresses }) =>
    sdk.collection.removeFromAllowlist(collectionAddress, addresses),
  onSuccess: (_, variables) => {
    // ✅ Invalidate allowlist queries for all affected users
    queryClient.invalidateQueries({
      queryKey: ['allowlist', variables.collectionAddress]
    });
  },
});

// Fix setAllowlistOnly invalidation
const setAllowlistOnly = useMutation({
  mutationFn: ({ collectionAddress, enabled }) =>
    sdk.collection.setAllowlistOnly(collectionAddress, enabled),
  onSuccess: (_, variables) => {
    // ✅ Invalidate allowlistOnly queries
    queryClient.invalidateQueries({
      queryKey: ['allowlistOnly', variables.collectionAddress]
    });
  },
});
```

### Option 2: Remove Client-Side Check

**File:** `src/app/mint/[id]/page.tsx` (zuno-marketplace-mini)

Remove lines 97-103 (redundant check):
```typescript
// ❌ Remove this - contract enforces allowlist anyway
if (isAllowlistOnly && !isInAllowlist) {
  toast.error("You are not in the allowlist", { ... });
  return;
}
```

**Rationale:** Contract already enforces allowlist. Client check only prevents unnecessary transaction but causes confusion when cache is stale.

---

## 9. Unresolved Questions

1. **Why does issue mention "error signature 0xf501reed5"?**
   - This is generic execution revert
   - Need actual transaction hash to confirm if it's `Collection__NotInAllowlist` or different error
   - Could be unrelated issue (payment, timing, supply)

2. **Is ownerMint affected?**
   - `ownerMint` bypasses all checks (lines 76-87 in ERC721Collection.sol)
   - Should work regardless of allowlist state
   - Need to verify if issue reported was using regular mint or ownerMint

3. **Test coverage gaps?**
   - No integration tests found for allowlist operations + mint flow
   - Should add E2E test: add address → verify mint succeeds

---

## 10. Test Recommendations

### Contract Tests (Already Passing ✅)
- `test_AddToAllowlist_Success()` - BaseCollectionCoverage.t.sol
- `test_Mint_Allowlist_Success()` - UnitBaseCollectionTest.t.sol
- `test_Mint_Allowlist_RevertNotAllowlisted()` - UnitBaseCollectionTest.t.sol

### Missing Tests
```solidity
// Should add to test suite:
function test_AllowlistAddThenMint() public {
    // 1. Add user to allowlist
    // 2. Verify isInAllowlist(user) == true
    // 3. Mint should succeed
}

function test_AllowlistRemoveThenMint() public {
    // 1. Add user to allowlist
    // 2. Remove user from allowlist
    // 3. Verify isInAllowlist(user) == false
    // 4. Mint should revert with NotInAllowlist
}

function test_DisableAllowlistOnlyThenMint() public {
    // 1. Enable allowlistOnly
    // 2. Add user to allowlist
    // 3. Disable allowlistOnly
    // 4. User should still be able to mint (in PUBLIC stage now)
}
```

---

## 11. Conclusion

**Root Cause:** React Query cache invalidation mismatch in `useCollection.ts`

**Impact:** Frontend shows stale allowlist status after mutations

**Fix Complexity:** Low (change query keys in 3 mutation hooks)

**Recommendation:**
1. Fix query key invalidation in `useCollection.ts` (Option 1)
2. Add integration tests for allowlist operations
3. Remove redundant client-side checks in mint page (Option 2)
4. Add debug logging to track cache state changes

---

## Files Analyzed

**Contracts:**
- `E:\zuno-marketplace-contracts\src\common\BaseCollection.sol` (297 lines)
- `E:\zuno-marketplace-contracts\src\core\collection\ERC721Collection.sol` (114 lines)
- `E:\zuno-marketplace-contracts\src\core\collection\ERC1155Collection.sol` (127 lines)
- `E:\zuno-marketplace-contracts\src\errors\CollectionErrors.sol`

**SDK:**
- `E:\zuno-marketplace-sdk\src\modules\CollectionModule.ts` (1046 lines)
- `E:\zuno-marketplace-sdk\src\react\hooks\useCollection.ts` (281 lines)

**Frontend:**
- `E:\zuno-marketplace-mini\src\app\mint\[id]\page.tsx`
- `E:\zuno-marketplace-mini\src\app\collections\[id]\page.tsx`

**Tests:**
- `E:\zuno-marketplace-contracts\test\unit\collection\BaseCollectionCoverage.t.sol`
- `E:\zuno-marketplace-contracts\test\unit\collection\UnitBaseCollectionTest.t.sol`
- `E:\zuno-marketplace-contracts\test\unit\collection\UnitERC721CollectionTest.t.sol`
- `E:\zuno-marketplace-contracts\test\unit\collection\UnitERC1155CollectionTest.t.sol`
