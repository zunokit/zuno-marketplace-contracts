// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/auction/EnglishAuction.sol";
import "src/core/factory/AuctionFactory.sol";
import "src/core/proxy/EnglishAuctionImplementation.sol";
import "src/core/proxy/DutchAuctionImplementation.sol";
import "src/types/AuctionTypes.sol";
import "src/errors/AuctionErrors.sol";
import "test/mocks/MockERC721.sol";

/**
 * @title Auction Cancel Refund Verification
 * @notice Tests to verify users get refunds when auction is canceled
 * @dev Reproduces issue: "cancel auction các user tham gia không refund"
 */
contract AuctionCancelRefundVerificationTest is Test {
    AuctionFactory public auctionFactory;
    MockERC721 public mockERC721;

    address public constant MARKETPLACE_WALLET = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BIDDER1 = address(0x3);
    address public constant BIDDER2 = address(0x4);
    address public constant BIDDER3 = address(0x5);

    uint256 public constant START_PRICE = 1 ether;
    uint256 public constant DURATION = 1 days;

    function setUp() public {
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();
        auctionFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));

        mockERC721.mint(SELLER, 1);

        vm.deal(BIDDER1, 10 ether);
        vm.deal(BIDDER2, 10 ether);
        vm.deal(BIDDER3, 10 ether);
    }

    /**
     * @notice Test: Multiple users bid, seller cancels, verify ALL can withdraw
     */
    function test_CancelWithMultipleBids_AllCanWithdraw() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // Track balances before
        uint256 b1Before = BIDDER1.balance;
        uint256 b2Before = BIDDER2.balance;
        uint256 b3Before = BIDDER3.balance;

        // Three users bid sequentially
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        // Check pending refunds BEFORE cancel
        uint256 refund1_Before = auctionFactory.getPendingRefund(auctionId, BIDDER1);
        uint256 refund2_Before = auctionFactory.getPendingRefund(auctionId, BIDDER2);
        uint256 refund3_Before = auctionFactory.getPendingRefund(auctionId, BIDDER3);

        console.log("=== BEFORE CANCEL ===");
        console.log("BIDDER1 refund:", refund1_Before);
        console.log("BIDDER2 refund:", refund2_Before);
        console.log("BIDDER3 refund:", refund3_Before);

        assertEq(refund1_Before, 1 ether, "BIDDER1 should have 1 ETH refund from being outbid");
        assertEq(refund2_Before, 2 ether, "BIDDER2 should have 2 ETH refund from being outbid");
        assertEq(refund3_Before, 0, "BIDDER3 is highest bidder, no refund yet");

        // Seller cancels auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Check pending refunds AFTER cancel
        uint256 refund1_After = auctionFactory.getPendingRefund(auctionId, BIDDER1);
        uint256 refund2_After = auctionFactory.getPendingRefund(auctionId, BIDDER2);
        uint256 refund3_After = auctionFactory.getPendingRefund(auctionId, BIDDER3);

        console.log("=== AFTER CANCEL ===");
        console.log("BIDDER1 refund:", refund1_After);
        console.log("BIDDER2 refund:", refund2_After);
        console.log("BIDDER3 refund:", refund3_After);

        assertEq(refund1_After, 1 ether, "BIDDER1 should still have 1 ETH refund");
        assertEq(refund2_After, 2 ether, "BIDDER2 should still have 2 ETH refund");
        assertEq(refund3_After, 3 ether, "BIDDER3 should NOW have 3 ETH refund after cancel");

        // ALL users should be able to withdraw
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.withdrawBid(auctionId);

        // Verify final balances
        assertEq(BIDDER1.balance, b1Before, "BIDDER1 should have original balance back (10 - 1 + 1 = 10)");
        assertEq(BIDDER2.balance, b2Before, "BIDDER2 should have original balance back (10 - 2 + 2 = 10)");
        assertEq(BIDDER3.balance, b3Before, "BIDDER3 should have original balance back (10 - 3 + 3 = 10)");

        // Verify no more refunds available
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER1), 0);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER2), 0);
        assertEq(auctionFactory.getPendingRefund(auctionId, BIDDER3), 0);

        console.log("=== SUCCESS - All users refunded ===");
    }

    /**
     * @notice Test: User bids multiple times, gets outbid, auction canceled
     */
    function test_SameUserMultipleBids_Cancel_StillRefunded() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        uint256 b1Before = BIDDER1.balance;
        uint256 b2Before = BIDDER2.balance;
        console.log("=== BIDDER1 initial:", b1Before);
        console.log("=== BIDDER2 initial:", b2Before);

        // BIDDER1 bids first
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 1 ether}(auctionId);
        console.log("=== BIDDER1 after bid 1:", BIDDER1.balance);

        // BIDDER2 outbids
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 2 ether}(auctionId);
        console.log("=== BIDDER1 after outbid:", BIDDER1.balance);
        console.log("=== BIDDER1 refund:", auctionFactory.getPendingRefund(auctionId, BIDDER1));

        // BIDDER1 bids again (higher)
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: 3 ether}(auctionId);
        console.log("=== BIDDER1 after bid 2:", BIDDER1.balance);

        console.log("=== BIDDER1 refund before cancel:", auctionFactory.getPendingRefund(auctionId, BIDDER1));

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        uint256 b1Refund = auctionFactory.getPendingRefund(auctionId, BIDDER1);
        console.log("=== BIDDER1 refund after cancel:", b1Refund);

        assertEq(b1Refund, 4 ether, "BIDDER1 should have 4 ETH refund (1 ETH from outbid + 3 ETH from cancel)");

        // Withdraw
        vm.prank(BIDDER1);
        console.log("=== BIDDER1 before withdraw:", BIDDER1.balance);
        auctionFactory.withdrawBid(auctionId);
        console.log("=== BIDDER1 after withdraw:", BIDDER1.balance);

        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);

        assertEq(BIDDER1.balance, b1Before, "BIDDER1 should have original balance back (10 - 1 - 3 + 4 = 10)");
        assertEq(BIDDER2.balance, b2Before, "BIDDER2 should have original balance back (10 - 2 + 2 = 10)");

        console.log("=== SUCCESS - Multiple bids handled correctly ===");
    }

    /**
     * @notice Test: Cancel immediately after first bid
     */
    function test_CancelImmediately_FirstBidderRefunded() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        uint256 b1Before = BIDDER1.balance;
        console.log("BIDDER1 initial balance:", b1Before);

        // First bid
        vm.prank(BIDDER1);
        uint256 balanceAfterBid = BIDDER1.balance;
        auctionFactory.placeBid{value: 1 ether}(auctionId);
        console.log("BIDDER1 balance after bid:", BIDDER1.balance);
        console.log("BIDDER1 balance change:", balanceAfterBid - BIDDER1.balance);

        // Cancel immediately
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Should have refund
        uint256 refund = auctionFactory.getPendingRefund(auctionId, BIDDER1);
        console.log("=== Immediate cancel refund:", refund);
        assertEq(refund, 1 ether);

        // Withdraw
        vm.prank(BIDDER1);
        uint256 balanceBeforeWithdraw = BIDDER1.balance;
        auctionFactory.withdrawBid(auctionId);
        console.log("BIDDER1 balance after withdraw:", BIDDER1.balance);
        console.log("BIDDER1 received:", BIDDER1.balance - balanceBeforeWithdraw);

        assertEq(BIDDER1.balance, b1Before); // Should have original balance back (10 - 1 + 1 = 10)

        console.log("=== SUCCESS - Immediate cancel refund works ===");
    }
}
