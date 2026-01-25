# CRITICAL BUG: Refund Overpayment

## Date
2026-01-25 08:32

## Severity
**CRITICAL** - Users receive MORE ETH than they bid when withdrawing refunds

## Bug Description

When users withdraw their pending refunds after auction cancellation, they receive **extra ETH** beyond their bid amounts.

### Test Evidence

| Test | Expected Balance | Actual Balance | Extra |
|------|------------------|----------------|-------|
| Cancel with 3 bidders | 10 ETH | 13 ETH | +3 ETH |
| Same user multiple bids | 9 ETH | 13 ETH | +4 ETH |
| Immediate cancel | 10 ETH | 11 ETH | +1 ETH |

## Root Cause (Hypothesis)

The extra ETH (~10% of bids) suggests **fee redistribution error**. Possible causes:

1. **Marketplace fee being refunded** - When bid is placed, 2-10% fee goes to marketplace. During refund, this fee might be incorrectly included.

2. **Double counting** - The `_processBid` function might be adding BOTH the full bid AND some fee amount to `pendingRefunds`.

3. **Fee calculation error** - `_distributeFees` might be called incorrectly during bid processing.

## Code Locations to Investigate

### EnglishAuction.sol
- `_processBid()` (line 288-307) - Bid processing and refund logic
- `cancelAuction()` (line 436-488) - Cancellation refund
- `withdrawBid()` (line 126-151) - Withdrawal mechanism

### BaseAuction.sol
- `_distributeFees()` (line 701-726) - Fee distribution logic
- `_calculateFees()` - Fee calculation

## Affected Scenarios

1. ✅ English auction with bids → **AFFECTED**
2. ✅ Multiple sequential bidders → **AFFECTED**
3. ✅ Same user bids multiple times → **AFFECTED**
4. ❌ Dutch auctions (no bidding) → **NOT AFFECTED**

## Impact

**HIGH SEVERITY** - Users can extract extra ETH from the protocol:
- Repeatedly bid and cancel auctions
- Withdraw refunds to get extra ETH
- Drains marketplace/seller funds

## Next Steps

1. ✅ Created reproduction test: `AuctionCancelRefundVerification.t.sol`
2. ⏳ Investigate `_processBid` and `_distributeFees` interaction
3. ⏳ Fix fee distribution logic
4. ⏳ Add tests to prevent regression

## Test File

`test/unit/marketplace/AuctionCancelRefundVerification.t.sol`

Run with:
```bash
forge test --match-path "test/unit/marketplace/AuctionCancelRefundVerification.t.sol" -vvv
```
