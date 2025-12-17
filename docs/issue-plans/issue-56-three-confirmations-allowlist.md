# Issue #56: Three Confirmations for Allowlist Collection Creation

## Issue Summary
**Title**: Investigating why `Zuno Contracts` requires three confirmations in Metamask when implementing allow lists of feature create collection that are expected to be twice.

**Expected**: 2 confirmations
**Actual**: 3 confirmations

**Affected Components**:
- `ERC721CollectionFactory.sol`
- `ERC1155CollectionFactory.sol`
- `ERC721Collection.sol`
- `ERC1155Collection.sol`
- SDK Collection Module

## Root Cause Analysis

### Current Flow (3 Transactions)

The three confirmations occur because the operation is split into three separate transactions:

| # | Transaction | Purpose |
|---|-------------|---------|
| 1 | `createCollection()` | Deploy collection proxy + initialize basic params |
| 2 | `addToAllowlist()` | Add addresses to allowlist |
| 3 | `setAllowlistOnly()` | Enable allowlist-only minting mode |

### Why This Design Exists
1. **Modularity**: Allowlist can be updated after creation
2. **Flexibility**: Some collections start public, then add allowlist later
3. **Gas Efficiency**: Basic collection creation is cheaper without allowlist

### The Problem
For the common case of "create collection WITH allowlist", users expect a single or dual transaction flow, not three separate confirmations.

## Proposed Solutions

### Option A: Batch Initialization (Recommended)
Enhance the factory's `createCollection()` to accept allowlist parameters upfront.

**Contract Changes**:
```solidity
// ERC721CollectionFactory.sol
function createCollectionWithAllowlist(
    CollectionParams calldata params,
    address[] calldata allowlistAddresses,
    bool enableAllowlistOnly
) external returns (address) {
    // 1. Create and initialize collection
    address collection = _createCollection(params);

    // 2. Add addresses to allowlist (if any)
    if (allowlistAddresses.length > 0) {
        ICollection(collection).batchAddToAllowlist(allowlistAddresses);
    }

    // 3. Enable allowlist-only mode (if requested)
    if (enableAllowlistOnly) {
        ICollection(collection).setAllowlistOnly(true);
    }

    emit CollectionCreatedWithAllowlist(collection, allowlistAddresses.length, enableAllowlistOnly);
    return collection;
}
```

**Result**: 1 confirmation for everything

### Option B: Multicall Pattern
Add a multicall function to execute multiple calls in one transaction.

```solidity
// Collection.sol
function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
    results = new bytes[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
        (bool success, bytes memory result) = address(this).delegatecall(data[i]);
        require(success, "Multicall failed");
        results[i] = result;
    }
    return results;
}
```

**SDK Usage**:
```typescript
const multicallData = [
  collection.interface.encodeFunctionData('batchAddToAllowlist', [addresses]),
  collection.interface.encodeFunctionData('setAllowlistOnly', [true])
];
await collection.multicall(multicallData);
```

**Result**: 2 confirmations (create + multicall)

### Option C: SDK Batching (No Contract Changes)
Use SDK to batch transactions using EIP-4337 or similar account abstraction.

**Result**: Depends on user's wallet support

## Implementation Plan (Option A - Recommended)

### Phase 1: Contract Changes

#### 1.1 Add Batch Functions to Collections
```solidity
// ICollection.sol (interface)
interface ICollection {
    function batchAddToAllowlist(address[] calldata addresses) external;
}

// ERC721Collection.sol
function batchAddToAllowlist(address[] calldata addresses) external onlyOwner {
    for (uint256 i = 0; i < addresses.length; i++) {
        _allowlist[addresses[i]] = true;
    }
    emit AllowlistBatchUpdated(addresses, true);
}
```

#### 1.2 Add Factory Function
```solidity
// ERC721CollectionFactory.sol
function createCollectionWithAllowlist(
    CollectionParams calldata params,
    address[] calldata allowlistAddresses,
    bool enableAllowlistOnly
) external nonReentrant returns (address collection) {
    // Create collection
    collection = _deployAndInitialize(params);

    // Setup allowlist in one call
    if (allowlistAddresses.length > 0 || enableAllowlistOnly) {
        ICollection(collection).setupAllowlist(allowlistAddresses, enableAllowlistOnly);
    }

    return collection;
}
```

#### 1.3 Add Combined Setup Function
```solidity
// ERC721Collection.sol
function setupAllowlist(
    address[] calldata addresses,
    bool enableAllowlistOnly
) external onlyOwner {
    // Add all addresses
    for (uint256 i = 0; i < addresses.length; i++) {
        _allowlist[addresses[i]] = true;
    }

    // Set mode
    s_allowlistOnly = enableAllowlistOnly;

    emit AllowlistSetup(addresses.length, enableAllowlistOnly);
}
```

### Phase 2: SDK Changes
```typescript
// CollectionModule.ts
async createCollectionWithAllowlist(params: {
  name: string;
  symbol: string;
  // ... other params
  allowlist: string[];
  allowlistOnly: boolean;
}): Promise<{ collectionAddress: string; txHash: string }> {
  const tx = await this.factory.createCollectionWithAllowlist(
    {
      name: params.name,
      symbol: params.symbol,
      // ... other params
    },
    params.allowlist,
    params.allowlistOnly
  );

  const receipt = await tx.wait();
  const event = receipt.events?.find(e => e.event === 'CollectionCreatedWithAllowlist');

  return {
    collectionAddress: event?.args?.collection,
    txHash: receipt.transactionHash
  };
}
```

### Phase 3: Backward Compatibility
Keep existing separate functions for flexibility:
- `createCollection()` - Basic creation
- `addToAllowlist()` - Add addresses later
- `setAllowlistOnly()` - Toggle mode
- `createCollectionWithAllowlist()` - **NEW** Combined function

## Files to Modify

| File | Change |
|------|--------|
| `src/core/collection/ERC721Collection.sol` | Add `setupAllowlist()`, `batchAddToAllowlist()` |
| `src/core/collection/ERC1155Collection.sol` | Add `setupAllowlist()`, `batchAddToAllowlist()` |
| `src/core/factory/ERC721CollectionFactory.sol` | Add `createCollectionWithAllowlist()` |
| `src/core/factory/ERC1155CollectionFactory.sol` | Add `createCollectionWithAllowlist()` |
| `src/events/CollectionEvents.sol` | Add `CollectionCreatedWithAllowlist`, `AllowlistSetup` |
| `E:/zuno-marketplace-sdk/src/modules/CollectionModule.ts` | Add new method |
| `test/unit/collection/*.t.sol` | Add tests for new functions |

## Test Cases
```solidity
function test_CreateCollectionWithAllowlist_SingleTransaction() public {
    address[] memory allowlist = new address[](3);
    allowlist[0] = alice;
    allowlist[1] = bob;
    allowlist[2] = carol;

    address collection = factory.createCollectionWithAllowlist(
        defaultParams,
        allowlist,
        true // enableAllowlistOnly
    );

    // Verify allowlist is set
    assertTrue(ICollection(collection).isAllowlisted(alice));
    assertTrue(ICollection(collection).isAllowlisted(bob));
    assertTrue(ICollection(collection).isAllowlisted(carol));

    // Verify mode is set
    assertTrue(ICollection(collection).isAllowlistOnly());
}

function test_CreateCollectionWithAllowlist_EmptyAllowlist() public {
    address[] memory emptyList = new address[](0);

    address collection = factory.createCollectionWithAllowlist(
        defaultParams,
        emptyList,
        false
    );

    assertFalse(ICollection(collection).isAllowlistOnly());
}

function test_CreateCollectionWithAllowlist_LargeAllowlist() public {
    // Test with 100 addresses
    address[] memory largeList = new address[](100);
    for (uint i = 0; i < 100; i++) {
        largeList[i] = address(uint160(i + 1));
    }

    address collection = factory.createCollectionWithAllowlist(
        defaultParams,
        largeList,
        true
    );

    // Verify all added
    for (uint i = 0; i < 100; i++) {
        assertTrue(ICollection(collection).isAllowlisted(largeList[i]));
    }
}
```

## Gas Considerations
- Single transaction is more gas-efficient than 3 separate transactions
- Batch adding addresses scales linearly: ~5,000 gas per address
- Maximum recommended allowlist size per transaction: ~500 addresses (to stay under block gas limit)

## Acceptance Criteria
1. Creating collection with allowlist requires only 1 MetaMask confirmation
2. All allowlist addresses are correctly added
3. AllowlistOnly mode is correctly set
4. Backward compatibility maintained with existing functions
5. All existing tests pass
6. New tests added for combined function
7. Gas cost is lower than 3 separate transactions
