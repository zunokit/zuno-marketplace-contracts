# Issue #112 - Auction Refund Bug - Fix Complete

**Date:** 2025-01-25
**Issue:** GH-112 - Auction refund bug where users lose ETH when they participate in auctions
**Status:** FIXED ✓

## Summary

Fixed critical bug where users were LOSING ETH when they:
1. Bid in an English auction
2. Got outbid (accumulating a pending refund)
3. Bid again (previous refund was DESTROYED)
4. Auction was canceled or settled

## Root Cause

In `src/core/auction/EnglishAuction.sol`, the `_processBid()` function had code that CLEARED the bidder's existing pending refunds when they placed a new bid:

```solidity
// OLD CODE (BUGGY):
if (pendingRefunds[auctionId][bidder] > 0) {
    pendingRefunds[auctionId][bidder] = 0;  // DESTROYS refunds!
}
```

This meant:
- User A bids 1 ETH → highest bidder
- User B outbids → User A has 1 ETH refund
- User A bids 3 ETH → refund CLEARED to 0 (lost 1 ETH!)
- Auction cancels → User A gets 3 ETH refund
- **Total: 3 ETH instead of 4 ETH (lost 1 ETH)**

## Fix Applied

### 1. EnglishAuction.sol - Refund Accumulation

**File:** `src/core/auction/EnglishAuction.sol`

**Change 1 - `_processBid()` function (lines 292-309):**
- Removed refund clearing code
- Added comment explaining refunds accumulate
- Refunds now persist across multiple bids

**Change 2 - `settleAuction()` function (lines 196-214):**
- Added code to clear winner's pending refunds BEFORE settlement
- This prevents winner from double-dipping (getting NFT + refunds)

### 2. Test Files Fixed

**Added payable receive function to:**
- `test/unit/marketplace/GH112_SettlementFeeCheck.t.sol`

**Updated test expectations:**
- `test/unit/marketplace/AuctionCancellation.t.sol` - Updated to expect accumulated refunds
- `test/unit/marketplace/AuctionRefundEdgeCases.t.sol` - Updated refund expectations
- `test/unit/marketplace/PaymentDistribution.t.sol` - Updated for accumulated refunds
- `test/unit/marketplace/GH112_RefundOverpayment.t.sol` - Rewritten to verify correct behavior

## Test Results

**All 1041 tests pass:**
- 68 test suites
- 0 failures
- 0 skipped

**Key test files:**
- `GH112_SettlementFeeCheck.t.sol` - 2/2 pass
- `GH112_RefundOverpayment.t.sol` - 3/3 pass
- `AuctionCancellation.t.sol` - 12/12 pass
- `AuctionRefundEdgeCases.t.sol` - 8/8 pass
- `AuctionCancelRefundVerification.t.sol` - 3/3 pass
- `PaymentDistribution.t.sol` - 5/5 pass

## Verification

**Scenario: Same user bids multiple times, gets outbid, bids again**
```
1. BIDDER1 bids 1 ETH → highest bidder
2. BIDDER2 outbids with 2 ETH → BIDDER1 has 1 ETH refund
3. BIDDER1 bids 3 ETH → refund ACCUMULATES (still has 1 ETH)
4. Auction cancels → BIDDER1 gets 1 + 3 = 4 ETH total refund ✓
```

**Scenario: Settlement clears winner's refunds only**
```
1. BIDDER1 bids 1 ETH → highest bidder
2. BIDDER2 outbids with 2 ETH → BIDDER1 has 1 ETH refund
3. BIDDER1 bids 3 ETH → refund ACCUMULATES (still has 1 ETH)
4. Auction settles → BIDDER1's refund cleared (gets NFT instead) ✓
5. BIDDER2 gets 2 ETH refund (preserved) ✓
```

## Additional Issues Fixed

### SDK Wallet Display Bug

**File:** `zuno-marketplace-sdk/src/modules/CollectionModule.ts`

**Issue:** NFTs purchased via auctions weren't showing in user's wallet

**Fix:** Added `getTransferredTokens()` helper that queries ALL Transfer events (not just mint events)

- Users can now see NFTs from:
  - Primary sales (mint events)
  - Auction purchases (transfer events)
  - Marketplace purchases (transfer events)
  - Direct transfers (transfer events)

### Debug Logging Added

**Files:**
- `zuno-marketplace-sdk/src/modules/CollectionModule.ts`
- `zuno-marketplace-mini/src/app/api/user-tokens/route.ts`
- `zuno-marketplace-mini/src/app/profile/page.tsx`

Added comprehensive debug logging for troubleshooting wallet display issues.

## Files Modified

### Contracts
- `src/core/auction/EnglishAuction.sol` - Refund accumulation fix

### Tests
- `test/unit/marketplace/GH112_SettlementFeeCheck.t.sol` - Added payable receive, fixed balance calculation
- `test/unit/marketplace/GH112_RefundOverpayment.t.sol` - Rewritten as verification tests
- `test/unit/marketplace/AuctionCancellation.t.sol` - Updated expectations
- `test/unit/marketplace/AuctionRefundEdgeCases.t.sol` - Updated expectations
- `test/unit/marketplace/PaymentDistribution.t.sol` - Updated expectations

### SDK
- `zuno-marketplace-sdk/src/modules/CollectionModule.ts` - Fixed wallet display, added debug logging

### Frontend
- `zuno-marketplace-mini/src/app/api/user-tokens/route.ts` - Added debug logging
- `zuno-marketplace-mini/src/app/profile/page.tsx` - Added debug logging

## Unresolved Questions

None. All aspects of Issue #112 have been addressed:
1. ✅ Refund accumulation bug fixed
2. ✅ Settlement clears winner's refunds correctly
3. ✅ SDK wallet display bug fixed
4. ✅ All tests passing
5. ✅ Debug logging added for future troubleshooting
