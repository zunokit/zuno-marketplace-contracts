---
title: "Phase 01: Research Token Standard Detection"
description: "Analyze existing token detection and determine optimal strategy"
status: pending
priority: P1
effort: 1h
tags: [research, token-detection]
---

## Overview

Research existing token standard detection in SDK to determine optimal strategy for differentiating ERC721 vs ERC1155 when calling listing functions.

## Current Implementation

**Location:** `E:\zuno-marketplace-sdk\src\core\ContractRegistry.ts:173-220`

```typescript
async verifyTokenStandard(
  address: string,
  provider: ethers.Provider
): Promise<TokenStandard> {
  // Uses ERC165 supportsInterface()
  const ERC721_INTERFACE_ID = '0x80ac58cd';
  const ERC1155_INTERFACE_ID = '0xd9b67a26';

  // Checks ERC721 first, then ERC1155
  // Returns 'ERC721' | 'ERC1155' | 'Unknown'
}
```

## Usage in ExchangeModule

**Location:** `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts:56-81`

```typescript
private async getExchangeContract(
  collectionAddress: string,
  provider: ethers.Provider,
  signer?: ethers.Signer
): Promise<ethers.Contract> {
  const tokenType = await this.contractRegistry.verifyTokenStandard(
    collectionAddress,
    provider
  );

  const contractType = tokenType === 'ERC1155'
    ? 'ERC1155NFTExchange'
    : 'ERC721NFTExchange';

  return this.contractRegistry.getContract(contractType, ...);
}
```

## Key Findings

1. **Already Implemented**: `verifyTokenStandard()` exists and works
2. **Already Used**: `getExchangeContract()` already detects token type
3. **Detection Method**: ERC165 `supportsInterface()` - reliable standard
4. **Return Type**: `TokenStandard = 'ERC721' | 'ERC1155' | 'Unknown'`

## Strategy

**Option A: Detect Before Each Listing** (Recommended)
- Pros: Always accurate, handles mixed collections
- Cons: Extra RPC call per listing
- Implementation: Call `verifyTokenStandard()` in `listNFT()` and `batchListNFT()`

**Option B: Cache Detection Result**
- Pros: Better performance
- Cons: Cache invalidation complexity, potential stale data
- Implementation: Add `Map<string, TokenStandard>` cache in ExchangeModule

**Decision**: Use Option A for correctness. Can optimize with caching later if needed.

## Implementation Steps

1. Import `TokenStandard` type in ExchangeModule
2. Call `verifyTokenStandard()` before listing
3. Use token type to determine parameter structure
4. Handle 'Unknown' token type gracefully

## Requirements

- Maintain existing `getExchangeContract()` behavior
- Add token detection in listing functions
- Provide clear error for unsupported token types

## Related Code Files

- `E:\zuno-marketplace-sdk\src\core\ContractRegistry.ts` - Detection implementation
- `E:\zuno-marketplace-sdk\src\modules\ExchangeModule.ts` - Usage location
- `E:\zuno-marketplace-sdk\src\types\contracts.ts` - TokenStandard type

## Success Criteria

- [ ] Document token detection strategy
- [ ] Verify `verifyTokenStandard()` works correctly
- [ ] Confirm no breaking changes to existing code
- [ ] Performance impact acceptable (<100ms per detection)

## Security Considerations

- ERC165 spoofing possible (malicious contract claims to be ERC721/1155)
- Contract call reverts handled gracefully
- No trust assumptions on detection result

## Next Steps

Proceed to Phase 02: Update type definitions to add amount fields.
