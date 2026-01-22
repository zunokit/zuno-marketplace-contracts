---
title: "Phase 07: Write Tests"
description: "Write comprehensive tests for ERC1155 and ERC721 listing functionality"
status: pending
priority: P1
effort: 1h
tags: [testing, unit-tests, integration-tests]
---

## Overview

Write comprehensive tests to verify ERC1155 listings work correctly with amount parameter while maintaining backward compatibility with ERC721 listings.

## Requirements

### Functional Requirements
1. Test ERC1155 single listing with amount
2. Test ERC1155 single listing without amount (default)
3. Test ERC1155 batch listing with amounts array
4. Test ERC1155 batch listing without amounts array (default)
5. Test ERC721 single listing (backward compatibility)
6. Test ERC721 batch listing (backward compatibility)
7. Test validation errors
8. Test formatListing extraction

### Non-Functional Requirements
- High test coverage (>90%)
- Clear test names and descriptions
- Isolated test cases
- Fast execution

## Related Code Files

### Files to Create

**`E:\zuno-marketplace-sdk\src\__tests__\modules\ExchangeModule.erc1155.test.ts`**
- New test file for ERC1155-specific tests

### Files to Update

**`E:\zuno-marketplace-sdk\src\__tests__\modules\ExchangeModule.test.ts`**
- Add ERC1155 test cases to existing test suite

## Test Cases

### Test Suite 1: Single Listing

```typescript
describe('ExchangeModule.listNFT - ERC1155', () => {
  it('should list ERC1155 with explicit amount', async () => {
    // Setup mock ERC1155 contract
    // Mock verifyTokenStandard to return 'ERC1155'
    // Call listNFT with amount='10'
    // Verify contract called with 5 params
    // Verify amount parameter passed correctly
  });

  it('should list ERC1155 with default amount=1', async () => {
    // Setup mock ERC1155 contract
    // Call listNFT without amount
    // Verify contract called with amount='1'
  });

  it('should reject ERC1155 listing with amount=0', async () => {
    // Call listNFT with amount='0'
    // Expect validation error
  });

  it('should list ERC721 without amount (backward compatible)', async () => {
    // Setup mock ERC721 contract
    // Mock verifyTokenStandard to return 'ERC721'
    // Call listNFT without amount
    // Verify contract called with 4 params (no amount)
  });
});
```

### Test Suite 2: Batch Listing

```typescript
describe('ExchangeModule.batchListNFT - ERC1155', () => {
  it('should batch list ERC1155 with explicit amounts', async () => {
    // Setup mock ERC1155 contract
    // Call batchListNFT with amounts=['5', '10', '15']
    // Verify contract called with 5 params
    // Verify amounts array passed correctly
  });

  it('should batch list ERC1155 with default amounts', async () => {
    // Setup mock ERC1155 contract
    // Call batchListNFT without amounts
    // Verify contract called with amounts=['1', '1', '1']
  });

  it('should reject batch listing with mismatched array lengths', async () => {
    // Call batchListNFT with tokenIds.length=3, amounts.length=2
    // Expect validation error
  });

  it('should reject batch listing with amount=0', async () => {
    // Call batchListNFT with amounts=['1', '0', '5']
    // Expect validation error at index 1
  });

  it('should batch list ERC721 without amounts (backward compatible)', async () => {
    // Setup mock ERC721 contract
    // Call batchListNFT without amounts
    // Verify contract called with 4 params (no amounts)
  });
});
```

### Test Suite 3: Listing Entity

```typescript
describe('ExchangeModule.formatListing - ERC1155', () => {
  it('should extract amount from ERC1155 listing', async () => {
    // Mock contract listing data with amount='10'
    // Call formatListing
    // Verify listing.amount === '10'
  });

  it('should return undefined amount for ERC721 listing', async () => {
    // Mock contract listing data without amount
    // Call formatListing
    // Verify listing.amount === undefined
  });
});
```

### Test Suite 4: Validation

```typescript
describe('validateListNFTParams - Amount Validation', () => {
  it('should reject amount=0', () => {
    // Expect error when amount='0'
  });

  it('should reject negative amount', () => {
    // Expect error when amount='-1'
  });

  it('should reject invalid amount format', () => {
    // Expect error when amount='invalid'
  });

  it('should accept valid amount', () => {
    // Should not throw when amount='10'
  });
});

describe('validateBatchListNFTParams - Amounts Validation', () => {
  it('should reject mismatched array lengths', () => {
    // Expect error when amounts.length !== tokenIds.length
  });

  it('should reject amount=0 in array', () => {
    // Expect error when amounts=['1', '0', '5']
  });

  it('should accept valid amounts array', () => {
    // Should not throw when amounts=['5', '10', '15']
  });
});
```

### Test Suite 5: Token Detection

```typescript
describe('Token Standard Detection', () => {
  it('should detect ERC1155 and pass 5 params', async () => {
    // Mock verifyTokenStandard to return 'ERC1155'
    // Verify contract called with correct params
  });

  it('should detect ERC721 and pass 4 params', async () => {
    // Mock verifyTokenStandard to return 'ERC721'
    // Verify contract called with correct params
  });

  it('should handle Unknown token type gracefully', async () => {
    // Mock verifyTokenStandard to return 'Unknown'
    // Verify error handling or default behavior
  });
});
```

## Test Setup

### Mock Contracts

```typescript
// Mock ERC1155 Exchange Contract
const mockERC1155Exchange = {
  listNFT: vi.fn().mockResolvedValue(mockTx),
  batchListNFT: vi.fn().mockResolvedValue(mockTx),
};

// Mock ERC721 Exchange Contract
const mockERC721Exchange = {
  listNFT: vi.fn().mockResolvedValue(mockTx),
  batchListNFT: vi.fn().mockResolvedValue(mockTx),
};

// Mock verifyTokenStandard
vi.spyOn(contractRegistry, 'verifyTokenStandard').mockImplementation(
  async (address: string) => {
    if (address === MOCK_ERC1155_ADDRESS) return 'ERC1155';
    if (address === MOCK_ERC721_ADDRESS) return 'ERC721';
    return 'Unknown';
  }
);
```

## Success Criteria

- [ ] All ERC1155 listing tests pass
- [ ] All ERC721 backward compatibility tests pass
- [ ] All validation tests pass
- [ ] Code coverage >90% for modified files
- [ ] No test flakiness
- [ ] Tests run in <5 seconds

## Testing Strategy

1. **Unit Tests**: Test individual functions in isolation
2. **Integration Tests**: Test full flow with mocks
3. **Edge Cases**: Test boundary conditions (0, negative, invalid)
4. **Backward Compatibility**: Ensure ERC721 still works

## Next Steps

Proceed to Phase 08: Update documentation with examples and usage guide.

## References

- Existing Tests: `E:\zuno-marketplace-sdk\src\__tests__\modules\ExchangeModule.test.ts`
- Test Patterns: Follow existing test structure
- Mock Patterns: Use existing mock setup
