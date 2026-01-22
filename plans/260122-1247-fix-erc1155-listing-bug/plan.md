---
title: "Fix ERC1155 Listing Bug"
description: "Add missing amount parameter to ExchangeModule for ERC1155 listings"
status: completed
priority: P1
effort: 6h
branch: develop-claude
tags: [bug, erc1155, exchange, sdk]
created: 2026-01-22
completed: 2026-01-22
---

## Overview

Fix critical bug preventing ERC1155 NFT listings in zuno-marketplace-sdk. SDK's ExchangeModule missing `amount` parameter for ERC1155 contract calls, causing transaction failures.

## Key Issues

1. **Single Listing** (`listNFT`): SDK passes 4 params, ERC1155 expects 5 (missing `amount`)
2. **Batch Listing** (`batchListNFT`): SDK passes 4 params, ERC1155 expects 5 (missing `amounts` array)
3. **Type Definitions**: Missing `amount` fields in params and listing entity
4. **Data Extraction**: `formatListing()` doesn't extract amount from contract data

## Root Cause

SDK doesn't differentiate between ERC721 (4 params) and ERC1155 (5 params) contracts. Both use same parameter array, causing parameter mismatch for ERC1155.

## Contract Signatures

**ERC721 Exchange** (4 params):
```solidity
function listNFT(address, uint256, uint256, uint256)
function batchListNFT(address, uint256[], uint256[], uint256)
```

**ERC1155 Exchange** (5 params):
```solidity
function listNFT(address, uint256, uint256, uint256, uint256) // +amount
function batchListNFT(address, uint256[], uint256[], uint256[], uint256) // +amounts
```

## Phases

- [Phase 01](./phase-01-research-token-standard-detection.md) - Research token standard detection strategy ✅ DONE 2026-01-22
- [Phase 02](./phase-02-update-type-definitions.md) - Add amount fields to type definitions ✅ DONE 2026-01-22
- [Phase 03](./phase-03-implement-single-listing-fix.md) - Fix listNFT() for ERC1155 ✅ DONE 2026-01-22
- [Phase 04](./phase-04-implement-batch-listing-fix.md) - Fix batchListNFT() for ERC1155 ✅ DONE 2026-01-22
- [Phase 05](./phase-05-update-listing-entity.md) - Extract amount in formatListing() ✅ DONE 2026-01-22
- [Phase 06](./phase-06-add-validation.md) - Add validation for amount parameter ✅ DONE 2026-01-22
- [Phase 07](./phase-07-write-tests.md) - Test ERC1155 and ERC721 listings ✅ DONE 2026-01-22
- [Phase 08](./phase-08-update-documentation.md) - Document amount parameter usage ✅ DONE 2026-01-22

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Token Detection | Use existing `verifyTokenStandard()` | Already implemented, uses ERC165 |
| Amount Required | Required for ERC1155, optional for ERC721 | Contract enforces amount > 0 for ERC1155 |
| Default Amount | Default to '1' for ERC1155 if omitted | User-friendly, matches single token expectation |
| Validation | Validate amount > 0 for ERC1155 | Prevents contract reverts |
| Breaking Change | No (optional field) | Maintains backward compatibility |

## Success Criteria

- [x] ERC1155 single listing works with amount parameter
- [x] ERC1155 batch listing works with amounts array
- [x] ERC721 listings continue to work without amount
- [x] Listing entity includes amount field for ERC1155
- [x] All tests pass (ERC721 + ERC1155)
- [x] Documentation updated with examples

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Token detection fails | Medium | Catch errors, provide clear message |
| Performance hit from detection | Low | Consider caching token standard |
| Array length mismatch in batch | Low | Validate amounts.length === tokenIds.length |
| Backward compatibility break | High | Make amount optional, default to '1' |

## References

- Debugger Report: `E:\zuno-marketplace-sdk\plans\reports\debugger-260122-1244-erc1155-listing-bug.md`
- ERC1155 Exchange: `E:\zuno-marketplace-contracts\src\core\exchange\ERC1155NFTExchange.sol`
- ERC721 Exchange: `E:\zuno-marketplace-contracts\src\core\exchange\ERC721NFTExchange.sol`
- ContractRegistry: `E:\zuno-marketplace-sdk\src\core\ContractRegistry.ts`
