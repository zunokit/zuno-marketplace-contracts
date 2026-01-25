# ERC1155 Listing Bug - Task Extraction Report

**Date:** 2026-01-22 12:53
**Plan:** Fix ERC1155 Listing Bug
**Work Context:** E:\zuno-marketplace-sdk
**Reports:** E:\zuno-marketplace-sdk\plans\reports\
**Plans:** E:\zuno-marketplace-sdk\plans\

---

## Executive Summary

**Total Phases:** 8
**Total Tasks:** 47
**Estimated Effort:** 6 hours
**Priority:** P1 (Critical Bug Fix)

**Scope:** Fix SDK bug in `zunokit/zuno-marketplace-sdk` - ExchangeModule missing `amount` parameter for ERC1155 listings.

---

## Phase-by-Phase Task Breakdown

### Phase 01: Research Token Standard Detection (1h)

**Status:** Pending
**Priority:** P1
**Dependencies:** None

**Tasks:**
1. Import `TokenStandard` type in ExchangeModule
2. Call `verifyTokenStandard()` in listing functions
3. Handle 'Unknown' token type gracefully
4. Document token detection strategy decision
5. Verify `verifyTokenStandard()` works correctly
6. Confirm no breaking changes to existing code
7. Assess performance impact (<100ms per detection)

**Key Findings:**
- `verifyTokenStandard()` already implemented in ContractRegistry
- Uses ERC165 `supportsInterface()` - reliable
- Already used in `getExchangeContract()`
- Decision: Detect before each listing (Option A)

**Related Files:**
- `E:\zuno-marketplace-sdk\src\core\ContractRegistry.ts:173-220`
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:56-81`
- `E:\zuno-marketplace-sdk\src\types\contracts.ts`

---

### Phase 02: Update Type Definitions (0.5h)

**Status:** Pending
**Priority:** P1
**Dependencies:** None

**Tasks:**
1. Add `amount?: string` to `ListNFTParams` interface (lines 87-93)
2. Add JSDoc comments for amount parameter with default note
3. Add `amounts?: string[]` to `BatchListNFTParams` interface (lines 98-103)
4. Add JSDoc comments for amounts array with length requirement
5. Add `amount?: string` to `Listing` entity interface (lines 50-61)
6. Add JSDoc comments explaining ERC1155 vs ERC721 difference
7. Verify TypeScript compiles without errors
8. Test backward compatibility with existing ERC721 code

**Files to Modify:**
- `E:\zuno-marketplace-sdk\src\types\contracts.ts`
- `E:\zuno-marketplace-sdk\src\types\entities.ts`

**Type Changes:**
```typescript
// ListNFTParams
amount?: string; // @default "1", @example "10"

// BatchListNFTParams
amounts?: string[]; // Length must match tokenIds.length

// Listing entity
amount?: string; // undefined for ERC721, value for ERC1155
```

---

### Phase 03: Implement Single Listing Fix (1.5h)

**Status:** Pending
**Priority:** P1
**Dependencies:** Phase 01 (token detection), Phase 02 (types)

**Tasks:**
1. Import `TokenStandard` type in ExchangeModule (line ~7-14)
2. Add `amount` to destructured params in `listNFT()`
3. Add token detection call before contract interaction
4. Add log statement for detected token type
5. Implement conditional parameter array (ERC721: 4 params, ERC1155: 5 params)
6. Default amount to '1' for ERC1155 if omitted
7. Update `sendTransaction()` call with dynamic params
8. Verify ERC1155 listing works with explicit amount
9. Verify ERC1155 listing works without amount (defaults to '1')
10. Verify ERC721 listing continues to work (backward compatible)

**Files to Modify:**
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:132-169`

**Code Logic:**
```typescript
const tokenType = await this.contractRegistry.verifyTokenStandard(
  collectionAddress,
  provider
);

const contractParams = tokenType === 'ERC1155'
  ? [collectionAddress, tokenId, amount || '1', priceInWei, duration] // 5 params
  : [collectionAddress, tokenId, priceInWei, duration]; // 4 params
```

---

### Phase 04: Implement Batch Listing Fix (1.5h)

**Status:** Pending
**Priority:** P1
**Dependencies:** Phase 01 (token detection), Phase 02 (types)

**Tasks:**
1. Add `amounts` to destructured params in `batchListNFT()`
2. Add token detection call before contract interaction
3. Add array length validation (amounts.length === tokenIds.length)
4. Add log statement for detected token type
5. Implement conditional parameter array (ERC721: 4 params, ERC1155: 5 params)
6. Default amounts to array of '1's for ERC1155 if omitted
7. Update `sendTransaction()` call with dynamic params
8. Verify ERC1155 batch listing works with explicit amounts
9. Verify ERC1155 batch listing works without amounts (defaults to ['1','1',...])
10. Verify ERC721 batch listing continues to work (backward compatible)

**Files to Modify:**
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:561-597`

**Validation Logic:**
```typescript
if (amounts !== undefined && amounts.length !== tokenIds.length) {
  throw this.error(ErrorCodes.INVALID_PARAMETER,
    'Amounts array length must match token IDs array length');
}

const normalizedAmounts = amounts || tokenIds.map(() => '1');
```

**Contract Params:**
```typescript
const contractParams = tokenType === 'ERC1155'
  ? [normalizedCollection, tokenIds, normalizedAmounts, pricesInWei, duration] // 5 params
  : [normalizedCollection, tokenIds, pricesInWei, duration]; // 4 params
```

---

### Phase 05: Update Listing Entity (0.5h)

**Status:** Pending
**Priority:** P2
**Dependencies:** Phase 02 (Listing type updated)

**Tasks:**
1. Extract `amount` field from contract listing data (line ~106-109)
2. Convert amount BigInt to string
3. Handle missing amount gracefully (undefined for old data)
4. Add `amount` field to returned Listing object
5. Update function comment to mention amount extraction
6. Verify ERC1155 listings show correct amount
7. Verify ERC721 listings have amount = undefined
8. Test handling of missing data.amount (old listings)

**Files to Modify:**
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:519-556`

**Code Addition:**
```typescript
const amount = data.amount
  ? BigInt(data.amount).toString()
  : undefined;

return {
  // ... existing fields
  amount, // Include in Listing
};
```

---

### Phase 06: Add Validation (0.5h)

**Status:** Pending
**Priority:** P2
**Dependencies:** Phase 02 (types updated)

**Tasks:**
1. Add amount validation to `validateListNFTParams()`
2. Validate amount > 0 using BigInt
3. Add error handling for invalid amount format
4. Add `validateBatchListNFTParams()` function (if doesn't exist)
5. Validate amounts array length matches tokenIds length
6. Validate each amount > 0 in array with index in error message
7. Add validation call to `batchListNFT()` function
8. Test amount='0' rejection
9. Test negative amount rejection
10. Test invalid BigInt format rejection

**Files to Modify:**
- `E:\zuno-marketplace-sdk\src\utils\errors.ts`
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts` (add validation call)

**Validation Logic:**
```typescript
// Single listing
if (params.amount !== undefined) {
  const amount = BigInt(params.amount);
  if (amount <= 0) {
    throw new ZunoSDKError(ErrorCodes.INVALID_PARAMETER,
      'Amount must be greater than 0');
  }
}

// Batch listing
if (params.amounts !== undefined) {
  if (params.amounts.length !== params.tokenIds.length) {
    throw new ZunoSDKError(ErrorCodes.INVALID_PARAMETER,
      'Amounts array must have the same length as token IDs array');
  }
  for (let i = 0; i < params.amounts.length; i++) {
    const amount = BigInt(params.amounts[i]);
    if (amount <= 0) {
      throw new ZunoSDKError(ErrorCodes.INVALID_PARAMETER,
        `Amount at index ${i} must be greater than 0`);
    }
  }
}
```

---

### Phase 07: Write Tests (1h)

**Status:** Pending
**Priority:** P1
**Dependencies:** Phases 03-06 (implementation complete)

**Tasks:**

**Test Suite 1: Single Listing (5 tests)**
1. Test ERC1155 listing with explicit amount='10'
2. Test ERC1155 listing with default amount=1
3. Test ERC1155 listing with amount='0' (should fail)
4. Test ERC721 listing without amount (backward compatible)
5. Test contract called with correct params (5 vs 4)

**Test Suite 2: Batch Listing (5 tests)**
6. Test ERC1155 batch listing with amounts=['5','10','15']
7. Test ERC1155 batch listing with default amounts
8. Test batch listing with mismatched array lengths (should fail)
9. Test batch listing with amount='0' in array (should fail)
10. Test ERC721 batch listing without amounts (backward compatible)

**Test Suite 3: Listing Entity (3 tests)**
11. Test extract amount from ERC1155 listing
12. Test amount=undefined for ERC721 listing
13. Test handling missing data.amount gracefully

**Test Suite 4: Validation (4 tests)**
14. Test reject amount='0'
15. Test reject negative amount
16. Test reject invalid amount format
17. Test accept valid amount

**Test Suite 5: Batch Validation (3 tests)**
18. Test reject mismatched array lengths
19. Test reject amount='0' in array
20. Test accept valid amounts array

**Test Suite 6: Token Detection (3 tests)**
21. Test detect ERC1155 and pass 5 params
22. Test detect ERC721 and pass 4 params
23. Test handle Unknown token type gracefully

**Files to Create:**
- `E:\zuno-marketplace-sdk\src\__tests__\modules\ExchangeModule.erc1155.test.ts`

**Files to Update:**
- `E:\zuno-marketplace-sdk\src\__tests__\modules\ExchangeModule.test.ts`

**Success Criteria:**
- All tests pass
- Code coverage >90% for modified files
- Tests run in <5 seconds
- No test flakiness

---

### Phase 08: Update Documentation (0.5h)

**Status:** Pending
**Priority:** P2
**Dependencies:** All implementation phases complete

**Tasks:**

**Documentation Tasks (12 tasks):**
1. Create `E:\zuno-marketplace-sdk\docs\erc1155-listing-guide.md`
2. Document amount parameter in ListNFTParams JSDoc
3. Document amounts parameter in BatchListNFTParams JSDoc
4. Provide ERC1155 single listing example
5. Provide ERC1155 default amount example
6. Provide ERC1155 batch listing example
7. Provide ERC721 backward compatibility example
8. Document validation rules
9. Provide error handling examples
10. Create migration guide
11. Add FAQ section
12. Update CHANGELOG.md with changes

**README Updates:**
- Add ERC1155 examples section
- Link to comprehensive guide
- Note backward compatibility

**Changelog Entry:**
```markdown
## [Unreleased]

### Added
- ERC1155 listing support with configurable amounts
- `amount` parameter to ListNFTParams (optional, defaults to '1')
- `amounts` array to BatchListNFTParams (optional, defaults to ['1','1',...])
- `amount` field to Listing entity

### Fixed
- Fixed ERC1155 listing bug - now correctly passes amount parameter to contract
- Fixed ERC1155 batch listing - now correctly passes amounts array to contract

### Changed
- ExchangeModule now auto-detects token standard (ERC721 vs ERC1155)
- Listing entity includes amount field for ERC1155 listings
```

**Success Criteria:**
- Clear, concise documentation
- Practical code examples
- Migration guide available
- FAQ covers common questions

---

## Dependencies Map

```
Phase 01 (Research) ─────────────────────────────────────┐
                                                          │
Phase 02 (Types) ────────────────────────────────────────┤
                                                          │
Phase 03 (Single Listing) ───────┬───────────────────────┤
                                 │                       │
Phase 04 (Batch Listing) ────────┼───────────────────────┤
                                 │                       │
Phase 05 (Listing Entity) ───────┼───────────────────────┤
                                 │                       │
Phase 06 (Validation) ───────────┴───────────────────────┤
                                                         │
Phase 07 (Tests) ─────────────────────────────────────────┤
                                                         │
Phase 08 (Documentation) ─────────────────────────────────┘
```

**Critical Path:**
1. Phase 01 → Phase 02 → Phase 03 → Phase 07 → Phase 08
2. Phase 01 → Phase 02 → Phase 04 → Phase 07 → Phase 08

**Parallel Execution Opportunities:**
- Phase 05 can run parallel to Phase 03/04 (after Phase 02)
- Phase 06 can run parallel to Phase 05 (after Phase 02)

---

## Required Skills/Tools

### Skills to Activate:
1. **sequential-thinking** - Analyze token detection logic and parameter mapping
2. **debugging** - Verify implementation matches contract signatures
3. **code-reviewer** - Review all code changes after implementation

### Tools Needed:
1. **TypeScript compiler** - Verify type definitions compile
2. **Jest** - Run test suite
3. **ethers.js** - Contract interaction testing
4. **Git** - Branch management (develop-claude)

### Agent Delegation Chain:
1. **planner** → Create detailed implementation plan (already done)
2. **developer** → Implement all phases (01-08)
3. **code-simplifier** → Refine implementation code
4. **tester** → Write and run tests (Phase 07)
5. **code-reviewer** → Review final implementation
6. **docs-manager** → Update documentation (Phase 08)

---

## Ambiguities & Blockers

### Ambiguities:
1. **Token Detection Performance**: Option A (detect each time) chosen, but performance impact unclear in production
   - **Resolution**: Monitor in production, add caching if needed (future enhancement)

2. **Amount Default for ERC721**: Plan says "not required", but should we reject if provided?
   - **Resolution**: Allow but ignore for ERC721 (user-friendly)

3. **Backward Compatibility**: Plan says "no breaking changes", but need to verify existing ERC721 tests pass
   - **Resolution**: Run existing test suite before and after changes

### Blockers:
1. **None Identified** - All dependencies clear

### Risk Items:
1. **Contract Registry Changes**: If `verifyTokenStandard()` behavior changes, impacts all phases
   - **Mitigation**: Verify contract registry stability first

2. **Type Definition Rollout**: If types change but implementation incomplete, compilation fails
   - **Mitigation**: Complete type changes and implementation in same PR

3. **Test Data Mocking**: Need accurate contract mocks for testing
   - **Mitigation**: Use existing mock patterns from ExchangeModule.test.ts

---

## Recommended Implementation Order

### Sequential Approach (Recommended for correctness):
1. **Phase 01** (0.5h) - Verify token detection works
2. **Phase 02** (0.5h) - Update types first (minimal risk)
3. **Phase 03** (1.5h) - Fix single listing (core issue)
4. **Phase 04** (1.5h) - Fix batch listing (related issue)
5. **Phase 05** (0.5h) - Update listing entity (data layer)
6. **Phase 06** (0.5h) - Add validation (safety layer)
7. **Phase 07** (1h) - Write tests (verification)
8. **Phase 08** (0.5h) - Update docs (documentation)

**Total: 6h**

### Parallel Approach (If time-constrained):
**Sprint 1:**
- Phase 01 + Phase 02 (1h) - Research and types

**Sprint 2:**
- Phase 03 (1.5h) - Single listing
- Phase 05 (0.5h) - Listing entity (parallel)

**Sprint 3:**
- Phase 04 (1.5h) - Batch listing
- Phase 06 (0.5h) - Validation (parallel)

**Sprint 4:**
- Phase 07 (1h) - Tests

**Sprint 5:**
- Phase 08 (0.5h) - Documentation

**Total: 5h (with 2 developers, 1h parallel savings)

---

## Success Criteria Validation

### Contract Signatures Match:
- [ ] ERC721 listNFT: 4 params ✓
- [ ] ERC1155 listNFT: 5 params ✓
- [ ] ERC721 batchListNFT: 4 params ✓
- [ ] ERC1155 batchListNFT: 5 params ✓

### Type Safety:
- [ ] TypeScript compiles without errors
- [ ] All interfaces updated with amount fields
- [ ] JSDoc comments added

### Functionality:
- [ ] ERC1155 single listing works
- [ ] ERC1155 batch listing works
- [ ] ERC721 backward compatible
- [ ] Listing entity includes amount

### Quality:
- [ ] All tests pass (>90% coverage)
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] Changelog updated

---

## Unresolved Questions

1. **Performance Baseline**: What is current RPC call latency for token detection? Need to measure before optimization.

2. **Caching Strategy**: If detection is slow (>100ms), should we cache per-collection? Need production metrics first.

3. **Error Handling**: If `verifyTokenStandard()` returns 'Unknown', should we default to ERC721 or throw error?

4. **Test Coverage**: What is current test coverage for ExchangeModule? Need baseline to measure improvement.

5. **Deployment**: Is this a hotfix or scheduled release? Affects testing rigor and documentation detail.

6. **Contract Version**: Are there multiple versions of ERC1155Exchange contract deployed? Need to verify signature consistency.

---

## Next Steps

### Immediate Actions:
1. **Create TodoWrite list** from all 47 tasks above
2. **Delegate to developer agent** with work context: `E:\zuno-marketplace-sdk`
3. **Activate skills**: sequential-thinking, debugging
4. **Start implementation** with Phase 01

### After Implementation:
1. **Delegate to code-simplifier** - Refine implementation
2. **Delegate to tester** - Run full test suite
3. **Delegate to code-reviewer** - Review all changes
4. **Delegate to docs-manager** - Update documentation
5. **Update plan.md** - Mark phases complete, update YAML frontmatter

### Completion Criteria:
- All 8 phases complete
- All tests passing
- Code reviewed and approved
- Documentation updated
- Changelog updated
- Ready for PR to main branch

---

**Report Generated:** 2026-01-22 12:53
**Total Tasks:** 47 tasks across 8 phases
**Estimated Time:** 6 hours
**Work Context:** E:\zuno-marketplace-sdk (NOT contracts repo)
