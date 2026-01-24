// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/auction/EnglishAuction.sol";
import "src/core/factory/AuctionFactory.sol";
import "src/core/proxy/EnglishAuctionImplementation.sol";
import "src/core/proxy/DutchAuctionImplementation.sol";
import "src/interfaces/IAuction.sol";
import "src/types/AuctionTypes.sol";
import "src/errors/AuctionErrors.sol";
import "test/mocks/MockERC721.sol";

/**
 * @title Auction Refund Edge Cases Test
 * @notice Comprehensive tests for all auction refund scenarios
 * @dev Tests edge cases in English auction refund mechanism
 */
contract AuctionRefundEdgeCasesTest is Test {
    // Contracts
    AuctionFactory public auctionFactory;
    EnglishAuction public englishAuction;
    MockERC721 public mockERC721;

    // Test addresses
    address public constant MARKETPLACE_WALLET = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BIDDER1 = address(0x3);
    address public constant BIDDER2 = address(0x4);
    address public constant BIDDER3 = address(0x5);
    address public constant BIDDER4 = address(0x6);

    // Constants
    uint256 public constant DEFAULT_START_PRICE = 1 ether;
    uint256 public constant DEFAULT_RESERVE_PRICE = 0.5 ether;
    uint256 public constant DEFAULT_DURATION = 1 days;

    function setUp() public {
        // Deploy contracts
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();
        auctionFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));
        englishAuction = EnglishAuction(address(englishImpl));

        // Mint test NFT
        mockERC721.mint(SELLER, 1);

        // Fund bidders
        vm.deal(BIDDER1, 10 ether);
        vm.deal(BIDDER2, 10 ether);
        vm.deal(BIDDER3, 10 ether);
        vm.deal(BIDDER4, 10 ether);
    }

    // ========================================================================
    // Edge Case 1: Same user bids multiple times, gets outbid, then bids again
    // ========================================================================

    function test_Refund_SameUserMultipleBids_Outbid_BidAgain() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721),
            1,
            1,
            DEFAULT_START_PRICE,
            0, // No reserve
            DEFAULT_DURATION
        );
        vm.stopPrank();

        // BIDDER1 bids 1 ETH
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 0); // Highest bidder, no refund

        // BIDDER2 outbids with 2 ETH
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether); // BIDDER1 refunded
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 0); // BIDDER2 is highest

        // BIDDER1 bids again with 3 ETH (should clear previous refund)
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 3 ether}(auctionId);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 0); // Refund cleared!
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 2 ether); // BIDDER2 refunded

        // Cancel auction - BIDDER1 should get refund for highest bid
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 3 ether); // Now has refund
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 2 ether);

        // Both can withdraw
        uint256 bidder1BalanceBefore = BIDDER1.balance;
        uint256 bidder2BalanceBefore = BIDDER2.balance;

        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);

        assertEq(BIDDER1.balance, bidder1BalanceBefore + 3 ether);
        assertEq(BIDDER2.balance, bidder2BalanceBefore + 2 ether);
    }

    // ========================================================================
    // Edge Case 2: Four sequential bidders, then cancel
    // ========================================================================

    function test_Refund_FourSequentialBidders_Cancel() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Four sequential bids
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER4);
        auctionFactory.placeBid{value: 4 ether}(auctionId);

        // Verify pending refunds before cancel
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 2 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER3), 3 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER4), 0); // Highest bidder

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // All should have refunds now
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 2 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER3), 3 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER4), 4 ether);

        // All can withdraw successfully
        uint256 balancesBefore = BIDDER1.balance + BIDDER2.balance + BIDDER3.balance + BIDDER4.balance;

        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);
        vm.prank(BIDDER3);
        auctionFactory.withdrawBid(auctionId);
        vm.prank(BIDDER4);
        auctionFactory.withdrawBid(auctionId);

        uint256 balancesAfter = BIDDER1.balance + BIDDER2.balance + BIDDER3.balance + BIDDER4.balance;
        assertEq(balancesAfter, balancesBefore + 10 ether);
    }

    // ========================================================================
    // Edge Case 3: Bid with exact amount (no excess)
    // ========================================================================

    function test_Refund_BidWithExactAmount_NoExcess() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Bid exact amount
        vm.prank(BIDDER1);
        uint256 balanceBefore = BIDDER1.balance;
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        // BIDDER2 outbids
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        // BIDDER1 should have exactly 1 ETH refund
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether);

        // Withdraw should return exactly 1 ETH
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);

        assertEq(BIDDER1.balance, balanceBefore);
    }

    // ========================================================================
    // Edge Case 4: Cancel immediately after first bid
    // ========================================================================

    function test_Refund_CancelImmediatelyAfterFirstBid() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // First bid
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        // Cancel immediately
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // BIDDER1 should have refund
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether);

        // Withdraw should work
        uint256 balanceBefore = BIDDER1.balance;
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        assertEq(BIDDER1.balance, balanceBefore + 1 ether);
    }

    // ========================================================================
    // Edge Case 5: Multiple users withdraw in different orders
    // ========================================================================

    function test_Refund_MultipleWithdrawOrders() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Three bids
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        // Cancel
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Withdraw in reverse order
        uint256 b3Before = BIDDER3.balance;
        vm.prank(BIDDER3);
        auctionFactory.withdrawBid(auctionId);
        assertEq(BIDDER3.balance, b3Before + 3 ether);

        uint256 b2Before = BIDDER2.balance;
        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);
        assertEq(BIDDER2.balance, b2Before + 2 ether);

        uint256 b1Before = BIDDER1.balance;
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        assertEq(BIDDER1.balance, b1Before + 1 ether);
    }

    // ========================================================================
    // Edge Case 6: Reserve price not met - all refunded
    // ========================================================================

    function test_Refund_ReserveNotMet_AllRefunded() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 5 ether, DEFAULT_DURATION // 5 ETH reserve
        );
        vm.stopPrank();

        // Bids below reserve
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        // Fast forward to end
        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        // Try to settle (reserve not met)
        vm.prank(BIDDER1);
        auctionFactory.settleAuction(auctionId);

        // All should be refunded
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 2 ether);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 3 ether);

        // Both can withdraw
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);
    }

    // ========================================================================
    // Edge Case 7: Partial withdrawal not possible (all or nothing)
    // ========================================================================

    function test_Refund_NoPartialWithdrawal() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Bid and get outbid
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        // BIDDER1 has 1 ETH refund
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 1 ether);

        // Withdraw all at once
        uint256 balanceBefore = BIDDER1.balance;
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);

        // Should be exactly 1 ETH returned
        assertEq(BIDDER1.balance, balanceBefore + 1 ether);

        // Second withdrawal should fail
        vm.prank(BIDDER1);
        vm.expectRevert(Auction__NoBidToRefund.selector);
        auctionFactory.withdrawBid(auctionId);
    }

    // ========================================================================
    // Edge Case 8: Zero address as bidder (should not happen but test safety)
    // ========================================================================

    function test_Refund_ZeroAddressCannotWithdraw() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, 1 ether, 0, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Normal bid
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        // Zero address cannot withdraw (will revert with no refund)
        vm.prank(address(0));
        vm.expectRevert(Auction__NoBidToRefund.selector);
        auctionFactory.withdrawBid(auctionId);
    }

}
