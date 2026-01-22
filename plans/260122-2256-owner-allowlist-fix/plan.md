---
title: "Fix Owner Allowlist Bypass in BaseCollection"
description: "Fix bug where collection owner cannot mint during allowlist stage without being on allowlist"
status: pending
priority: P1
effort: 2h
branch: develop-claude
tags: [bugfix, security, allowlist, owner, basecollection]
created: 2026-01-22
---

## Overview

Fix critical bug in `BaseCollection.sol` where the contract owner is incorrectly required to be on the allowlist during the allowlist minting stage. The owner should always be able to mint regardless of allowlist status.

**Root Cause:** Lines 186-188 in `_validateMintConditions()` lack owner exemption check.

**Impact:** High - Owner cannot mint during allowlist stage without manual allowlist addition.

## Phases

| Phase | Status | File |
|-------|--------|------|
| [Phase 01: Fix Implementation](./phase-01-fix-implementation.md) | pending | `phase-01-fix-implementation.md` |
| [Phase 02: Test Updates](./phase-02-test-updates.md) | pending | `phase-02-test-updates.md` |

## Key Dependencies

- None (standalone bugfix)

## Related Files

**To Modify:**
- `src/common/BaseCollection.sol` (lines 186-188)
- `test/unit/collection/UnitBaseCollectionTest.t.sol` (add owner mint test)
- `test/unit/collection/BaseCollectionCoverage.t.sol` (add coverage test)

## Quick Reference

**Fix Location:** `src/common/BaseCollection.sol:186-188`

**Current Code:**
```solidity
if (s_currentStage == MintStage.ALLOWLIST) {
    if (!s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

**Fixed Code:**
```solidity
if (s_currentStage == MintStage.ALLOWLIST) {
    if (to != owner() && !s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

## Success Criteria

- [ ] Owner can mint during allowlist stage without being on allowlist
- [ ] Non-owner still require allowlist access during allowlist stage
- [ ] All existing tests pass
- [ ] New test coverage for owner minting during allowlist stage
- [ ] No gas regression
