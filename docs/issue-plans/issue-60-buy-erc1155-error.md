# Issue #60: Buy NFT (ERC1155) Error - TransferToSellerFailed

## Issue Summary
**Title**: Buy NFT (ERC1155) error. But buy ERC721 working

**Error**: `NFTExchange__TransferToSellerFailed()` (selector: `0x2cfc4631`)

**Affected Components**:
- `ERC1155NFTExchange.sol`
- `NFTTransferLib.sol`

## Root Cause Analysis

### Error Location
The error is thrown in `ERC1155NFTExchange.sol` at lines 163 and 264:

```solidity
// Line 158-163
NFTTransferLib.TransferParams memory transferParams = NFTTransferLib.TransferParams(
    s_listing.contractAddress, s_listing.tokenId, m_purchaseAmount, s_listing.seller, msg.sender
);

NFTTransferLib.TransferResult memory transferResult = NFTTransferLib.transferERC1155(transferParams);
if (!transferResult.success) {
    revert NFTExchange__TransferToSellerFailed();
}
```

### Potential Root Causes

#### Cause A: Seller Lost Approval
The seller may have revoked approval for the exchange contract after listing.

**Check**: `IERC1155.isApprovedForAll(seller, exchangeAddress)`

#### Cause B: Seller No Longer Has Sufficient Balance
For ERC1155, the seller needs to maintain the token balance until sale.

**Check**: `IERC1155.balanceOf(seller, tokenId) >= amount`

#### Cause C: SDK Approval Flow Issue
The SDK might not be checking/requesting approval before purchase.

**Check**: `E:/zuno-marketplace-sdk/src/modules/ExchangeModule.ts`

#### Cause D: Contract Address Mismatch
The exchange might be using a different contract address than expected.

### Key Difference: ERC721 vs ERC1155

| Aspect | ERC721 | ERC1155 |
|--------|--------|---------|
| Transfer | `safeTransferFrom(from, to, tokenId)` | `safeTransferFrom(from, to, tokenId, amount, data)` |
| Balance Check | `ownerOf(tokenId) == seller` | `balanceOf(seller, tokenId) >= amount` |
| Approval | `getApproved(tokenId)` OR `isApprovedForAll` | `isApprovedForAll` only |

## Investigation Steps

### Step 1: Check NFTTransferLib.transferERC1155
```solidity
// src/libraries/NFTTransferLib.sol
function transferERC1155(TransferParams memory params) internal returns (TransferResult memory) {
    try IERC1155(params.nftContract).safeTransferFrom(
        params.from,
        params.to,
        params.tokenId,
        params.amount,
        ""
    ) {
        return TransferResult({success: true, errorMessage: ""});
    } catch Error(string memory reason) {
        return TransferResult({success: false, errorMessage: reason});
    } catch {
        return TransferResult({success: false, errorMessage: "Transfer failed"});
    }
}
```

### Step 2: Verify Approval in SDK
Check if SDK properly ensures approval before calling `buyNFT`:

```typescript
// Should exist in ExchangeModule.ts
async ensureApproval(nftContract: string, tokenId: number, amount: number) {
  const isApproved = await nft.isApprovedForAll(seller, exchangeAddress);
  if (!isApproved) {
    await nft.setApprovalForAll(exchangeAddress, true);
  }
}
```

### Step 3: Check Listing Validation
Verify that listing creation validates seller ownership:

```solidity
// In ERC1155NFTExchange.listNFT
NFTValidationLib.ValidationResult memory result = NFTValidationLib.validateERC1155(
    nftContract, tokenId, amount, msg.sender, address(this)
);
```

## Implementation Plan

### Phase 1: Diagnostic Improvements
- [ ] Add detailed error messages to `NFTTransferLib.transferERC1155`
- [ ] Log the actual revert reason from ERC1155 contract
- [ ] Add pre-transfer validation checks

### Phase 2: Contract Fixes (If Needed)
```solidity
// Add pre-purchase validation in ERC1155NFTExchange.sol
function _validatePurchase(bytes32 listingId, uint256 amount) internal view {
    Listing storage listing = s_listings[listingId];

    // Check seller still has tokens
    uint256 sellerBalance = IERC1155(listing.contractAddress).balanceOf(
        listing.seller,
        listing.tokenId
    );
    if (sellerBalance < amount) {
        revert NFTExchange__SellerInsufficientBalance();
    }

    // Check approval still valid
    bool isApproved = IERC1155(listing.contractAddress).isApprovedForAll(
        listing.seller,
        address(this)
    );
    if (!isApproved) {
        revert NFTExchange__ApprovalRevoked();
    }
}
```

### Phase 3: SDK Improvements
```typescript
// ExchangeModule.ts
async buyNFT(listingId: string, amount: number = 1): Promise<TransactionResult> {
  // Pre-flight checks
  const listing = await this.getListing(listingId);

  // Validate listing is still valid
  const [balance, isApproved] = await Promise.all([
    this.getSellerBalance(listing),
    this.checkSellerApproval(listing)
  ]);

  if (balance < amount) {
    throw new ZunoSDKError('INSUFFICIENT_SELLER_BALANCE',
      'Seller no longer has enough tokens');
  }

  if (!isApproved) {
    throw new ZunoSDKError('APPROVAL_REVOKED',
      'Seller has revoked marketplace approval');
  }

  // Proceed with purchase
  return this.contract.purchaseNFT(listingId, amount, { value: price });
}
```

## Files to Modify

| File | Change |
|------|--------|
| `src/core/exchange/ERC1155NFTExchange.sol` | Add pre-purchase validation |
| `src/libraries/NFTTransferLib.sol` | Improve error messages |
| `src/errors/NFTExchangeErrors.sol` | Add new error types |
| `E:/zuno-marketplace-sdk/src/modules/ExchangeModule.ts` | Add pre-flight checks |
| `test/unit/exchange/ERC1155NFTExchange.t.sol` | Add edge case tests |

## New Error Definitions
```solidity
// NFTExchangeErrors.sol
error NFTExchange__SellerInsufficientBalance();
error NFTExchange__ApprovalRevoked();
error NFTExchange__ListingStale();
```

## Test Cases
```solidity
function test_PurchaseERC1155_FailsWhenSellerBalanceInsufficient() public {}
function test_PurchaseERC1155_FailsWhenApprovalRevoked() public {}
function test_PurchaseERC1155_SuccessWithValidConditions() public {}
function test_PurchaseERC1155_PartialQuantityPurchase() public {}
```

## Acceptance Criteria
1. Clear error messages for ERC1155 purchase failures
2. Pre-flight validation before transaction submission
3. SDK provides user-friendly error handling
4. All existing tests continue to pass
5. New edge case tests added and passing
