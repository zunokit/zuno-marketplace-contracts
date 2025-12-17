# Issue #61: Canceled Auctions Still Displayed in My Auction Tab

## Issue Summary
**Title**: My auction tab in `Zuno Mini` display all auctions even though they have been canceled. Check again `Zuno Contracts`

**Affected Components**:
- `AuctionFactory.sol` - Query functions
- `BaseAuction.sol` - Auction status tracking
- Zuno Mini frontend - Auction display filtering

## Root Cause Analysis

### Investigation Areas

1. **Contract Level**: Check if `getUserAuctions()` or similar functions filter by status
2. **SDK Level**: Check if SDK filters canceled auctions
3. **Frontend Level**: Check if Zuno Mini applies status filters

### Auction Status Enum
```solidity
enum AuctionStatus {
    ACTIVE,      // 0
    ENDED,       // 1
    CANCELLED,   // 2
    SETTLED      // 3
}
```

### Potential Root Causes

#### Cause A: No Status Filter in Query Functions
The contract query functions might return ALL auctions regardless of status.

**Check in**: `src/core/auction/BaseAuction.sol` or `src/core/factory/AuctionFactory.sol`

#### Cause B: SDK Not Filtering
The SDK might fetch all auctions without filtering by status.

**Check in**: `E:/zuno-marketplace-sdk/src/modules/AuctionModule.ts`

#### Cause C: Frontend Not Filtering
Zuno Mini might display all returned auctions without client-side filtering.

**Check in**: `E:/zuno-marketplace-mini`

## Implementation Plan

### Phase 1: Contract Investigation
- [ ] Review `getAuction()`, `getUserAuctions()`, `getActiveAuctions()` functions
- [ ] Check if there are any view functions that return filtered auctions
- [ ] Verify auction status is correctly updated when canceled

### Phase 2: Add Filtered Query Functions (If Missing)
```solidity
/// @notice Returns active auctions for a user
function getUserActiveAuctions(address user) external view returns (bytes32[] memory) {
    bytes32[] memory allAuctions = s_userAuctions[user];
    uint256 activeCount = 0;

    // Count active auctions
    for (uint256 i = 0; i < allAuctions.length; i++) {
        if (s_auctions[allAuctions[i]].status == AuctionStatus.ACTIVE) {
            activeCount++;
        }
    }

    // Build result array
    bytes32[] memory activeAuctions = new bytes32[](activeCount);
    uint256 index = 0;
    for (uint256 i = 0; i < allAuctions.length; i++) {
        if (s_auctions[allAuctions[i]].status == AuctionStatus.ACTIVE) {
            activeAuctions[index++] = allAuctions[i];
        }
    }

    return activeAuctions;
}

/// @notice Returns auctions by status
function getAuctionsByStatus(AuctionStatus status) external view returns (bytes32[] memory);
```

### Phase 3: SDK Updates
```typescript
// Add filter options to getMyAuctions
interface AuctionFilterOptions {
  status?: AuctionStatus[];
  includeExpired?: boolean;
}

async getMyAuctions(options?: AuctionFilterOptions): Promise<Auction[]> {
  const auctions = await this.contract.getUserAuctions(this.signer.address);

  if (options?.status) {
    return auctions.filter(a => options.status.includes(a.status));
  }

  // Default: exclude CANCELLED
  return auctions.filter(a => a.status !== AuctionStatus.CANCELLED);
}
```

### Phase 4: Frontend Updates (Zuno Mini)
- [ ] Add status filter UI component
- [ ] Default to showing only ACTIVE auctions
- [ ] Add toggle to show all auctions including canceled

## Files to Modify

| Repository | File | Change |
|------------|------|--------|
| zuno-contracts | `src/core/auction/BaseAuction.sol` | Add `getUserActiveAuctions()`, `getAuctionsByStatus()` |
| zuno-contracts | `src/core/factory/AuctionFactory.sol` | Expose filtered query functions |
| zuno-contracts | `test/unit/auction/*.t.sol` | Add tests for filtered queries |
| zuno-sdk | `src/modules/AuctionModule.ts` | Add filter options to `getMyAuctions()` |
| zuno-mini | TBD | Apply status filter in UI |

## Test Cases
```solidity
function test_GetUserActiveAuctions_ExcludesCanceled() public {}
function test_GetUserActiveAuctions_ExcludesEnded() public {}
function test_GetAuctionsByStatus_ReturnsCorrectAuctions() public {}
function test_CancelAuction_UpdatesStatusCorrectly() public {}
```

## Acceptance Criteria
1. Canceled auctions are NOT displayed by default in "My Auctions" tab
2. User can optionally view canceled auctions with a filter
3. All auction statuses are correctly tracked and queryable
4. Gas-efficient implementation for query functions
