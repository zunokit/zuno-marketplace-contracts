# Implementation Plan: Fix ERC1155 Listing Bug

**Date:** 2026-01-22
**Issue:** #99 - Bug listing ERC1155
**Status:** Plan Complete
**Priority:** P1 (Critical)
**Estimated Effort:** 6 hours

---

## Executive Summary

Created comprehensive implementation plan to fix critical bug preventing ERC1155 NFT listings in zuno-marketplace-sdk. Root cause identified: SDK's `ExchangeModule` missing `amount` parameter for ERC1155 contract calls.

## Problem Statement

**Root Cause:** SDK passes 4 parameters to both ERC721 and ERC1155 listing functions, but ERC1155 contracts expect 5 parameters (including `amount`).

**Impact:**
- All ERC1155 single listings fail with `invalid BigNumberish value` error
- All ERC1155 batch listings fail with `invalid array value` error
- Core marketplace functionality non-functional for ERC1155 collections

## Solution Overview

**Strategy:** Detect token standard (ERC721 vs ERC1155) using existing `verifyTokenStandard()` function, then pass correct parameter array to contract.

**Key Design Decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Token Detection | Use existing `verifyTokenStandard()` | Already implemented, uses ERC165 standard |
| Amount Required | Required for ERC1155, optional for ERC721 | Contract enforces amount > 0 for ERC1155 |
| Default Amount | Default to '1' for ERC1155 if omitted | User-friendly, matches single token expectation |
| Breaking Change | No (optional field) | Maintains backward compatibility |
| Validation | Validate amount > 0 for ERC1155 | Prevents contract reverts |

## Implementation Phases

### Phase 1: Research Token Standard Detection (1h)
- Analyze existing `verifyTokenStandard()` implementation
- Confirm ERC165 detection method is reliable
- Document token detection strategy
- **Status:** Ready to implement

### Phase 2: Update Type Definitions (0.5h)
- Add `amount?: string` to `ListNFTParams`
- Add `amounts?: string[]` to `BatchListNFTParams`
- Add `amount?: string` to `Listing` entity
- Add JSDoc comments explaining usage
- **Files:** `src/types/contracts.ts`, `src/types/entities.ts`

### Phase 3: Implement Single Listing Fix (1.5h)
- Update `listNFT()` to detect token type
- Pass 5 params for ERC1155 (including amount)
- Pass 4 params for ERC721 (no amount)
- Default amount to '1' for ERC1155
- **File:** `src/modules/ExchangeModule.ts:132-169`

### Phase 4: Implement Batch Listing Fix (1.5h)
- Update `batchListNFT()` to detect token type
- Pass 5 params for ERC1155 (including amounts array)
- Pass 4 params for ERC721 (no amounts)
- Default amounts to array of '1's
- Validate array lengths match
- **File:** `src/modules/ExchangeModule.ts:561-597`

### Phase 5: Update Listing Entity (0.5h)
- Extract `amount` field from contract data in `formatListing()`
- Include amount in returned Listing entity
- Handle missing amount gracefully
- **File:** `src/modules/ExchangeModule.ts:519-556`

### Phase 6: Add Validation (0.5h)
- Validate amount > 0 for ERC1155 listings
- Validate amounts array length matches tokenIds
- Validate each amount > 0 in batch listings
- Provide clear error messages
- **Files:** `src/utils/errors.ts`

### Phase 7: Write Tests (1h)
- Test ERC1155 single listing with/without amount
- Test ERC1155 batch listing with/without amounts
- Test ERC721 backward compatibility
- Test validation errors
- Test formatListing extraction
- **Target:** >90% code coverage

### Phase 8: Update Documentation (0.5h)
- Add ERC1155 usage examples
- Document amount parameter behavior
- Create migration guide
- Update README and changelog
- **Files:** `README.md`, `CHANGELOG.md`

## Affected Files

| File | Lines | Changes |
|------|-------|---------|
| `src/types/contracts.ts` | 87-103 | Add amount/amounts fields |
| `src/types/entities.ts` | 50-61 | Add amount field to Listing |
| `src/modules/ExchangeModule.ts` | 132-169 | Update listNFT() with detection |
| `src/modules/ExchangeModule.ts` | 561-597 | Update batchListNFT() with detection |
| `src/modules/ExchangeModule.ts` | 519-556 | Extract amount in formatListing() |
| `src/utils/errors.ts` | New | Add validation for amount |

## Success Criteria

- [ ] ERC1155 single listing works with amount parameter
- [ ] ERC1155 batch listing works with amounts array
- [ ] ERC721 listings continue to work (backward compatible)
- [ ] Listing entity includes amount for ERC1155
- [ ] All tests pass (ERC721 + ERC1155)
- [ ] Code coverage >90%
- [ ] Documentation updated with examples

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Token detection fails | Medium | Catch errors, provide clear message |
| Performance hit from detection | Low | Extra RPC call acceptable for correctness |
| Array length mismatch | Low | Validate amounts.length === tokenIds.length |
| Backward compatibility break | High | Make amount optional, default to '1' |

## Contract Signatures

**ERC721 Exchange** (4 params):
```solidity
function listNFT(address m_contractAddress, uint256 m_tokenId, uint256 m_price, uint256 m_listingDuration)
function batchListNFT(address m_contractAddress, uint256[] m_tokenIds, uint256[] m_prices, uint256 m_listingDuration)
```

**ERC1155 Exchange** (5 params):
```solidity
function listNFT(address m_contractAddress, uint256 m_tokenId, uint256 m_amount, uint256 m_price, uint256 m_listingDuration)
function batchListNFT(address m_contractAddress, uint256[] m_tokenIds, uint256[] m_amounts, uint256[] m_prices, uint256 m_listingDuration)
```

## Key Insights

1. **Existing Infrastructure**: `verifyTokenStandard()` already implemented and tested
2. **Minimal Changes**: Only need to parameterize existing code paths
3. **No Breaking Changes**: Optional fields maintain backward compatibility
4. **Contract Alignment**: Matches contract expectations exactly
5. **User Experience**: Default to '1' for seamless ERC1155 usage

## Unresolved Questions

**Q1: Should we cache token standard detection results?**
- **Decision:** No for now. Extra RPC call (~100ms) acceptable for correctness. Can optimize later if needed.

**Q2: Should amount be required or optional for ERC1155?**
- **Decision:** Optional with default '1'. More user-friendly. Validation ensures > 0.

**Q3: How to handle Unknown token type from verifyTokenStandard()?**
- **Decision:** Default to ERC721 behavior (4 params). Contract will revert with clear error if wrong.

## Next Steps

1. Review and approve plan
2. Begin implementation with Phase 1
3. Execute phases sequentially
4. Run tests after Phase 6
5. Deploy after Phase 8 complete

## References

- Debugger Report: `E:\zuno-marketplace-sdk\plans\reports\debugger-260122-1244-erc1155-listing-bug.md`
- Plan Directory: `E:\zuno-marketplace-contracts\plans\260122-1247-fix-erc1155-listing-bug\`
- ERC1155 Exchange: `E:\zuno-marketplace-contracts\src\core\exchange\ERC1155NFTExchange.sol`
- ERC721 Exchange: `E:\zuno-marketplace-contracts\src\core\exchange\ERC721NFTExchange.sol`
- SDK Exchange Module: `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts`

---

**Plan Status:** ✅ Complete
**Ready for Implementation:** Yes
**Estimated Completion:** 6 hours
