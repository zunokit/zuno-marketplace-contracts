# Issue #55: Hardcoded ABI in Multiple Locations

## Issue Summary
**Title**: There are still hardcoded ABI in a few places check and improve Zuno Contracts.

**Affected Components**:
- SDK TypeScript files
- Solidity contract files (interface IDs)

## Root Cause Analysis

### Findings Summary
The codebase has hardcoded values in two categories:

1. **SDK**: Inline ABI snippets instead of using generated ABIs
2. **Contracts**: Hardcoded interface ID hex values instead of `type(IERC).interfaceId`

## Detailed Findings

### SDK Hardcoded ABIs

#### 1. ExchangeModule.ts (Lines 77-80)
```typescript
const erc721Abi = [
  'function isApprovedForAll(address owner, address operator) view returns (bool)',
  'function setApprovalForAll(address operator, bool approved)',
];
```

#### 2. AuctionModule.ts (Lines 99-102)
```typescript
const erc721Abi = [
  "function isApprovedForAll(address owner, address operator) view returns (bool)",
  "function setApprovalForAll(address operator, bool approved)",
];
```

#### 3. ContractRegistry.ts (Lines 181-189)
```typescript
const ERC721_INTERFACE_ID = '0x80ac58cd';
const ERC1155_INTERFACE_ID = '0xd9b67a26';
// ...
const contract = new ethers.Contract(
  address,
  ['function supportsInterface(bytes4 interfaceId) view returns (bool)'],
  // ...
);
```

### Contract Hardcoded Interface IDs

| File | Line | Hardcoded Value | Should Use |
|------|------|-----------------|------------|
| `AuctionFactory.sol` | 683 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `UserHub.sol` | 97 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `UserHub.sol` | 104 | `0xd9b67a26` | `type(IERC1155).interfaceId` |
| `OfferManager.sol` | 907 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `BaseAuction.sol` | 307 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `BaseAuction.sol` | 806 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `NFTValidationLib.sol` | 153 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `NFTValidationLib.sol` | 159 | `0xd9b67a26` | `type(IERC1155).interfaceId` |
| `Constants.sol` | 108 | `0x80ac58cd` | `type(IERC721).interfaceId` |
| `Constants.sol` | 111 | `0xd9b67a26` | `type(IERC1155).interfaceId` |
| `Constants.sol` | 114 | `0x2a55205a` | `type(IERC2981).interfaceId` |

## Implementation Plan

### Phase 1: Fix Contract Interface IDs

#### 1.1 Update Constants.sol
```solidity
// BEFORE
bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;
bytes4 public constant ERC1155_INTERFACE_ID = 0xd9b67a26;
bytes4 public constant ERC2981_INTERFACE_ID = 0x2a55205a;

// AFTER
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

bytes4 public constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;
bytes4 public constant ERC1155_INTERFACE_ID = type(IERC1155).interfaceId;
bytes4 public constant ERC2981_INTERFACE_ID = type(IERC2981).interfaceId;
```

#### 1.2 Update All Contract References
Replace all inline hex values with references to Constants or direct `type()` usage:

```solidity
// BEFORE
try IERC721(nftContract).supportsInterface(0x80ac58cd) returns (bool isERC721) {

// AFTER (Option 1: Use Constants)
import {Constants} from "src/common/Constants.sol";
try IERC721(nftContract).supportsInterface(Constants.ERC721_INTERFACE_ID) returns (bool isERC721) {

// AFTER (Option 2: Direct type())
try IERC721(nftContract).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
```

### Phase 2: Fix SDK Hardcoded ABIs

#### 2.1 Create ABI Constants File
```typescript
// src/constants/abis.ts
export const ERC721_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function safeTransferFrom(address from, address to, uint256 tokenId)',
  'function transferFrom(address from, address to, uint256 tokenId)',
  'function approve(address to, uint256 tokenId)',
  'function setApprovalForAll(address operator, bool approved)',
  'function getApproved(uint256 tokenId) view returns (address)',
  'function isApprovedForAll(address owner, address operator) view returns (bool)',
  'function supportsInterface(bytes4 interfaceId) view returns (bool)',
] as const;

export const ERC1155_ABI = [
  'function balanceOf(address account, uint256 id) view returns (uint256)',
  'function balanceOfBatch(address[] accounts, uint256[] ids) view returns (uint256[])',
  'function setApprovalForAll(address operator, bool approved)',
  'function isApprovedForAll(address account, address operator) view returns (bool)',
  'function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)',
  'function safeBatchTransferFrom(address from, address to, uint256[] ids, uint256[] amounts, bytes data)',
  'function supportsInterface(bytes4 interfaceId) view returns (bool)',
] as const;

export const ERC165_ABI = [
  'function supportsInterface(bytes4 interfaceId) view returns (bool)',
] as const;

// Interface IDs
export const INTERFACE_IDS = {
  ERC721: '0x80ac58cd',
  ERC1155: '0xd9b67a26',
  ERC2981: '0x2a55205a',
  ERC165: '0x01ffc9a7',
} as const;
```

#### 2.2 Update Modules to Use Constants
```typescript
// ExchangeModule.ts
import { ERC721_ABI, ERC1155_ABI } from '../constants/abis';

// Replace inline ABI
const nftContract = new ethers.Contract(address, ERC721_ABI, this.signer);
```

```typescript
// ContractRegistry.ts
import { ERC165_ABI, INTERFACE_IDS } from '../constants/abis';

async detectTokenStandard(address: string): Promise<TokenStandard> {
  const contract = new ethers.Contract(address, ERC165_ABI, this.provider);

  try {
    const isERC721 = await contract.supportsInterface(INTERFACE_IDS.ERC721);
    if (isERC721) return TokenStandard.ERC721;

    const isERC1155 = await contract.supportsInterface(INTERFACE_IDS.ERC1155);
    if (isERC1155) return TokenStandard.ERC1155;
  } catch {
    // Contract doesn't support ERC165
  }

  return TokenStandard.UNKNOWN;
}
```

### Phase 3: Alternative - Use Generated ABIs
For full type safety, use ABIs generated from compiled contracts:

```typescript
// Import from generated artifacts
import ERC721ABI from '../../../contracts/out/IERC721.sol/IERC721.json';
import ERC1155ABI from '../../../contracts/out/IERC1155.sol/IERC1155.json';

// Or use typechain generated types
import { IERC721__factory } from '../typechain';
```

## Files to Modify

### Contracts
| File | Change |
|------|--------|
| `src/common/Constants.sol` | Use `type(IERC).interfaceId` |
| `src/core/factory/AuctionFactory.sol` | Replace `0x80ac58cd` |
| `src/router/UserHub.sol` | Replace hardcoded IDs |
| `src/core/offers/OfferManager.sol` | Replace `0x80ac58cd` |
| `src/core/auction/BaseAuction.sol` | Replace `0x80ac58cd` (2 locations) |
| `src/libraries/NFTValidationLib.sol` | Replace `0x80ac58cd`, `0xd9b67a26` |

### SDK
| File | Change |
|------|--------|
| `src/constants/abis.ts` | **NEW** - Create centralized ABI constants |
| `src/modules/ExchangeModule.ts` | Import from constants |
| `src/modules/AuctionModule.ts` | Import from constants |
| `src/core/ContractRegistry.ts` | Import from constants |

## Test Cases

### Contract Tests
```solidity
function test_Constants_ERC721InterfaceId() public pure {
    assertEq(Constants.ERC721_INTERFACE_ID, type(IERC721).interfaceId);
}

function test_Constants_ERC1155InterfaceId() public pure {
    assertEq(Constants.ERC1155_INTERFACE_ID, type(IERC1155).interfaceId);
}

function test_Constants_ERC2981InterfaceId() public pure {
    assertEq(Constants.ERC2981_INTERFACE_ID, type(IERC2981).interfaceId);
}
```

### SDK Tests
```typescript
describe('ABI Constants', () => {
  it('should have correct ERC721 interface ID', () => {
    expect(INTERFACE_IDS.ERC721).toBe('0x80ac58cd');
  });

  it('should detect ERC721 contract', async () => {
    const result = await registry.detectTokenStandard(erc721Address);
    expect(result).toBe(TokenStandard.ERC721);
  });
});
```

## Benefits of This Change

1. **Maintainability**: Single source of truth for ABIs and interface IDs
2. **Type Safety**: TypeScript can validate ABI usage
3. **Consistency**: Same values used everywhere
4. **Readability**: `type(IERC721).interfaceId` is self-documenting
5. **Future-Proof**: If interface IDs ever change, only one place to update

## Acceptance Criteria
1. No hardcoded hex interface IDs in Solidity contracts
2. No inline ABI snippets in SDK TypeScript files
3. Centralized constants file in SDK
4. All existing tests pass
5. Documentation updated
6. Code review confirms no remaining hardcoded values
