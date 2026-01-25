# Debug Report: Owner Allowlist Bug (Issue #100)

**Date:** 2026-01-22
**Issue:** #100 - Owner add other address to allowlist but themselves not allow to mint
**Repository:** zunokit/zuno-marketplace-contracts

---

## Executive Summary

**Root Cause Identified:** Collection owners are NOT exempt from allowlist checks when using regular `mint()` functions.

**Impact:** HIGH - Owners cannot mint NFTs from their own collections during allowlist stage unless they explicitly add themselves to the allowlist mapping.

**Status:** Root cause confirmed, fix required

---

## Root Cause Analysis

### Location
- **File:** `E:\zuno-marketplace-contracts\src\common\BaseCollection.sol`
- **Function:** `_validateMintConditions()` (lines 161-189)
- **Specific Bug:** Lines 186-188

### Bug Details

```solidity
// Check allowlist if in allowlist stage
if (s_currentStage == MintStage.ALLOWLIST) {
    if (!s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

**Problem:** The allowlist check does NOT exempt the collection owner. When `s_allowlistOnly == true` or during allowlist stage, ALL addresses (including owner) must be in `s_allowlist` mapping.

### Expected Behavior
- Collection owners should ALWAYS be able to mint from their collections
- Owner exemption should apply to both ERC721 and ERC1155 collections
- Should work for regular `mint()` and `batchMint()` functions, not just `ownerMint()`

### Current Behavior
- Owner gets `Collection__NotInAllowlist()` error when:
  1. Allowlist-only mode is enabled (`s_allowlistOnly == true`)
  2. OR during allowlist stage (before `s_allowlistStageEnd`)
  3. Owner's address is NOT in `s_allowlist` mapping

---

## Affected Files

### Smart Contracts
1. **E:\zuno-marketplace-contracts\src\common\BaseCollection.sol**
   - Line 186-188: Allowlist check missing owner exemption
   - Function: `_validateMintConditions()`

2. **E:\zuno-marketplace-contracts\src\core\collection\ERC721Collection.sol**
   - Lines 39-47: `mint()` calls `checkMint()` which calls `_validateMintConditions()`
   - Lines 49-56: `batchMintERC721()` calls `checkMint()` which calls `_validateMintConditions()`

3. **E:\zuno-marketplace-contracts\src\core\collection\ERC1155Collection.sol**
   - Lines 38-53: `mint()` calls `checkMint()` which calls `_validateMintConditions()`
   - Lines 56-65: `batchMintERC1155()` calls `checkMint()` which calls `_validateMintConditions()`

### Workaround (NOT a fix)
- Use `ownerMint()` instead of `mint()`/`batchMint()`
- **Problem:** This is NOT a proper solution because:
  - Defeats the purpose of owner exemption
  - Creates two code paths for same operation
  - Poor UX - owners shouldn't need special function

---

## Evidence from Codebase

### Test File Confirms Bug
**File:** `E:\zuno-marketplace-contracts\test\integration\EndToEndTest.t.sol`
**Line 168:** Test explicitly adds owner to allowlist array

```solidity
address[] memory allowlistUsers = new address[](3);
allowlistUsers[0] = user1;
allowlistUsers[1] = user2;
allowlistUsers[2] = owner;  // Owner must add themselves!
```

This proves current implementation REQUIRES owners to add themselves, which is the bug.

### ownerMint() Bypasses Check
Both ERC721Collection.sol (line 76) and ERC1155Collection.sol (line 95) have `ownerMint()` with `onlyOwner` modifier that:
- Does NOT call `checkMint()`
- Bypasses all allowlist checks
- Only enforces maxSupply

**This confirms:** The bug is in `checkMint()` → `_validateMintConditions()` allowlist logic.

---

## Suggested Fix

### Fix Location
`E:\zuno-marketplace-contracts\src\common\BaseCollection.sol`
Lines 186-188 in `_validateMintConditions()`

### Code Change
**FROM:**
```solidity
// Check allowlist if in allowlist stage
if (s_currentStage == MintStage.ALLOWLIST) {
    if (!s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

**TO:**
```solidity
// Check allowlist if in allowlist stage (owner exempt)
if (s_currentStage == MintStage.ALLOWLIST) {
    if (to != owner() && !s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

### Rationale
- Uses `owner()` from Ownable contract (already inherited)
- Simple single-line condition check
- Minimal gas overhead
- Applies to both ERC721 and ERC1155 automatically
- Preserves security for non-owner addresses

---

## Testing Requirements

### Tests to Add
1. **Test owner can mint during allowlist stage without being in allowlist**
   - Setup: Create collection, enable allowlist-only, add OTHER users (not owner)
   - Action: Owner calls `mint()` / `batchMint()`
   - Expected: SUCCESS

2. **Test non-owner still blocked during allowlist stage**
   - Setup: Same as above
   - Action: Non-allowlisted user calls `mint()`
   - Expected: REVERT with `Collection__NotInAllowlist()`

3. **Test owner exemption with both ERC721 and ERC1155**
   - Verify fix works for both collection types

### Tests to Update
- `EndToEndTest.t.sol` line 168: Remove owner from allowlist array
- Add test case for owner minting without allowlist entry

---

## Unresolved Questions

1. **SDK Impact:** Does the SDK need updates to handle owner minting automatically?
   - Current SDK has `ownerMint()` function but users may be calling regular `mint()`
   - Consider: Should SDK auto-detect owner and use `ownerMint()`?

2. **Migration:** For collections already deployed, can owners add themselves as workaround?
   - Yes, via `addToAllowlist([ownerAddress])`
   - Document in release notes as temporary workaround

---

## Recommendations

### Immediate (Priority 1)
1. Fix `_validateMintConditions()` in BaseCollection.sol
2. Add comprehensive tests for owner allowlist exemption
3. Update existing tests that rely on owner being in allowlist

### Follow-up (Priority 2)
1. Update SDK documentation to clarify owner minting options
2. Consider SDK helper function that auto-selects `ownerMint()` vs `mint()` based on caller
3. Add integration test for full owner minting workflow

---

## Severity Assessment

**Severity:** HIGH
**Priority:** P0 (Critical Fix)

**Reasoning:**
- Breaks core functionality (owners cannot mint from own collections)
- Affects both ERC721 and ERC1155
- Poor user experience - unexpected restriction
- Simple workaround exists but shouldn't be necessary
- Low-risk fix (single condition check)
