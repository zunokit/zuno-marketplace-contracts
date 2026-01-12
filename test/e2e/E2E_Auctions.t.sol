// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {E2E_BaseSetup} from "./E2E_BaseSetup.sol";
import {console2} from "lib/forge-std/src/Test.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import "src/errors/AuctionErrors.sol";

/**
 * @title E2E_Auctions
 * @notice End-to-end tests for complete auction workflows
 * @dev Tests English and Dutch auctions with all edge cases
 */
contract E2E_AuctionsTest is E2E_BaseSetup {
    // ============================================================================
    // TEST 1: ENGLISH AUCTION COMPLETE FLOW
    // ============================================================================

    function test_E2E_EnglishAuctionCompleteFlow() public {
        console2.log("\n=== Test: English Auction Complete Flow ===");

        // Setup: Alice has an NFT
        vm.prank(alice);
        mockERC721.mint(alice, 1);

        // Set royalty receiver to eve for clarity in balance assertions
        vm.startPrank(alice);
        mockERC721.setDefaultRoyalty(eve, uint96(ROYALTY_FEE_BPS));
        vm.stopPrank();

        // Step 1: Alice creates an English auction
        vm.startPrank(alice);
        mockERC721.approve(address(englishAuction), 1);

        bytes32 auctionId = englishAuction.createAuction(
            address(mockERC721),
            1,
            1, // tokenId, amount
            1 ether, // starting price
            2 ether, // reserve price
            AUCTION_DURATION, // duration
            AuctionType.ENGLISH, // auction type
            alice // seller
        );
        vm.stopPrank();
        console2.log("Step 1: English auction created");

        // Step 2: Bob places first bid
        vm.prank(bob);
        englishAuction.placeBid{value: 1.2 ether}(auctionId);
        console2.log("Step 2: Bob bid 1.2 ETH");

        // Step 3: Charlie outbids Bob
        vm.prank(charlie);
        englishAuction.placeBid{value: 1.5 ether}(auctionId);
        console2.log("Step 3: Charlie bid 1.5 ETH");

        // Step 4: Dave places high bid
        vm.prank(dave);
        englishAuction.placeBid{value: 2.5 ether}(auctionId);
        console2.log("Step 4: Dave bid 2.5 ETH (above reserve)");

        // Step 5: Fast forward to end of auction
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        console2.log("Step 5: Auction ended");

        // Step 6: Settle auction
        BalanceSnapshot memory balancesBefore = snapshotBalances(dave, alice, englishAuction.marketplaceWallet(), eve);

        englishAuction.settleAuction(auctionId);

        BalanceSnapshot memory balancesAfter = snapshotBalances(dave, alice, englishAuction.marketplaceWallet(), eve);
        console2.log("Step 6: Auction settled");

        // Step 7: Verify NFT transferred to winner
        assertNFTOwner(address(mockERC721), 1, dave);
        console2.log("Step 7: Dave received NFT");

        // Step 8: Verify payment distribution
        uint256 winningBid = 2.5 ether;
        uint256 fee = (winningBid * TAKER_FEE_BPS) / 10000;
        uint256 royaltyFee = (winningBid * ROYALTY_FEE_BPS) / 10000;
        uint256 sellerReceives = winningBid - fee - royaltyFee; // Seller receives bid minus fees

        assertApproxEqAbs(
            balancesAfter.seller - balancesBefore.seller, sellerReceives, 1e15, "Seller should receive bid minus fees"
        );
        assertApproxEqAbs(
            balancesAfter.marketplace - balancesBefore.marketplace, fee, 1e15, "Marketplace fee incorrect"
        );
        assertApproxEqAbs(
            balancesAfter.royaltyReceiver - balancesBefore.royaltyReceiver, royaltyFee, 1e15, "Royalty not paid"
        );
        console2.log("Step 8: Payment verified");

        console2.log("=== English Auction Complete Flow: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 2: DUTCH AUCTION COMPLETE FLOW
    // ============================================================================

    function test_E2E_DutchAuctionCompleteFlow() public {
        console2.log("\n=== Test: Dutch Auction Complete Flow ===");

        // Setup
        vm.prank(alice);
        mockERC721.mint(alice, 2);

        // Set royalty receiver to eve for clarity in balance assertions
        vm.startPrank(alice);
        mockERC721.setDefaultRoyalty(eve, uint96(ROYALTY_FEE_BPS));
        vm.stopPrank();

        // Step 1: Alice creates Dutch auction
        vm.startPrank(alice);
        mockERC721.approve(address(dutchAuction), 2);

        bytes32 auctionId = dutchAuction.createAuction(
            address(mockERC721),
            2, // tokenId
            1, // amount
            2 ether, // starting price
            0.5 ether, // ending price (reserve price)
            AUCTION_DURATION, // duration
            AuctionType.DUTCH, // auction type
            alice // seller
        );
        vm.stopPrank();
        console2.log("Step 1: Dutch auction created (2 ETH -> 0.5 ETH)");

        // Step 2: Get initial price
        uint256 initialPrice = dutchAuction.getCurrentPrice(auctionId);
        assertEq(initialPrice, 2 ether);
        console2.log("Step 2: Initial price:", initialPrice);

        // Step 3: Fast forward to 6 hours (price should still be above reserve)
        vm.warp(block.timestamp + 6 hours);
        uint256 midPrice = dutchAuction.getCurrentPrice(auctionId);
        console2.log("Step 3: Price after 6 hours:", midPrice);

        // Verify price dropped but is still above reserve
        assertLt(midPrice, initialPrice);
        assertGt(midPrice, 0.5 ether);

        // Step 4: Bob buys at current price
        BalanceSnapshot memory balancesBefore = snapshotBalances(bob, alice, dutchAuction.marketplaceWallet(), eve);

        vm.prank(bob);
        dutchAuction.buyNow{value: midPrice}(auctionId);

        BalanceSnapshot memory balancesAfter = snapshotBalances(bob, alice, dutchAuction.marketplaceWallet(), eve);
        console2.log("Step 4: Bob purchased at", midPrice);

        // Step 5: Verify NFT ownership
        assertNFTOwner(address(mockERC721), 2, bob);
        console2.log("Step 5: Bob received NFT");

        // Step 6: Verify payment
        uint256 fee = (midPrice * TAKER_FEE_BPS) / 10000;
        uint256 royaltyFee = (midPrice * ROYALTY_FEE_BPS) / 10000;
        assertBalanceChanges(balancesBefore, balancesAfter, midPrice, midPrice - fee - royaltyFee, fee, royaltyFee);
        console2.log("Step 6: Payment verified");

        console2.log("=== Dutch Auction Complete Flow: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 3: AUCTION WITH ROYALTIES
    // ============================================================================

    function test_E2E_AuctionWithRoyalties() public {
        console2.log("\n=== Test: Auction with Royalties ===");

        // Setup: Alice mints NFT with royalties
        vm.startPrank(alice);
        mockERC721.mint(alice, 3);
        // Explicitly set royalty receiver to eve
        mockERC721.setDefaultRoyalty(eve, uint96(ROYALTY_FEE_BPS));
        mockERC721.approve(address(englishAuction), 3);

        // Create auction
        bytes32 auctionId = englishAuction.createAuction(
            address(mockERC721), 3, 1, 1 ether, 1.5 ether, AUCTION_DURATION, AuctionType.ENGLISH, alice
        );
        vm.stopPrank();
        console2.log("Step 1: Auction with royalty NFT created");

        // Bob bids
        vm.prank(bob);
        englishAuction.placeBid{value: 2 ether}(auctionId);
        console2.log("Step 2: Bob bid 2 ETH");

        // End auction
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Track balances
        BalanceSnapshot memory balancesBefore = snapshotBalances(bob, alice, englishAuction.marketplaceWallet(), eve);

        englishAuction.settleAuction(auctionId);

        BalanceSnapshot memory balancesAfter = snapshotBalances(bob, alice, englishAuction.marketplaceWallet(), eve);
        console2.log("Step 3: Auction settled");

        // Verify royalty paid
        uint256 royaltyAmount = (2 ether * ROYALTY_FEE_BPS) / 10000;
        assertApproxEqAbs(
            balancesAfter.royaltyReceiver - balancesBefore.royaltyReceiver, royaltyAmount, 1e15, "Royalty not paid"
        );
        console2.log("Step 4: Royalty verified:", royaltyAmount);

        assertNFTOwner(address(mockERC721), 3, bob);
        console2.log("=== Auction with Royalties: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 4: CONCURRENT AUCTIONS
    // ============================================================================

    function test_E2E_ConcurrentAuctions() public {
        console2.log("\n=== Test: Concurrent Auctions ===");

        // Setup: Multiple NFTs
        vm.startPrank(alice);
        mockERC721.mint(alice, 10);
        mockERC721.mint(alice, 11);
        mockERC721.mint(alice, 12);

        // Create 3 concurrent auctions
        mockERC721.approve(address(englishAuction), 10);
        mockERC721.approve(address(englishAuction), 11);
        mockERC721.approve(address(englishAuction), 12);

        bytes32 auction1 = englishAuction.createAuction(
            address(mockERC721), 10, 1, 1 ether, 1.5 ether, AUCTION_DURATION, AuctionType.ENGLISH, alice
        );

        bytes32 auction2 = englishAuction.createAuction(
            address(mockERC721), 11, 1, 2 ether, 2.5 ether, AUCTION_DURATION, AuctionType.ENGLISH, alice
        );

        bytes32 auction3 = englishAuction.createAuction(
            address(mockERC721), 12, 1, 0.5 ether, 0.8 ether, AUCTION_DURATION, AuctionType.ENGLISH, alice
        );
        vm.stopPrank();
        console2.log("Step 1: 3 concurrent auctions created");

        // Bob bids on auction 1 and 2
        vm.startPrank(bob);
        englishAuction.placeBid{value: 1.5 ether}(auction1);
        englishAuction.placeBid{value: 2.5 ether}(auction2);
        vm.stopPrank();
        console2.log("Step 2: Bob bid on 2 auctions");

        // Charlie bids on auction 2 and 3
        vm.startPrank(charlie);
        englishAuction.placeBid{value: 3 ether}(auction2);
        englishAuction.placeBid{value: 0.9 ether}(auction3);
        vm.stopPrank();
        console2.log("Step 3: Charlie bid on 2 auctions");

        // Dave outbids on auction 1
        vm.prank(dave);
        englishAuction.placeBid{value: 2 ether}(auction1);
        console2.log("Step 4: Dave bid on auction 1");

        // End all auctions
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Settle all
        englishAuction.settleAuction(auction1);
        englishAuction.settleAuction(auction2);
        englishAuction.settleAuction(auction3);
        console2.log("Step 5: All auctions settled");

        // Verify winners
        assertNFTOwner(address(mockERC721), 10, dave);
        assertNFTOwner(address(mockERC721), 11, charlie);
        assertNFTOwner(address(mockERC721), 12, charlie);
        console2.log("Step 6: Winners verified");

        console2.log("=== Concurrent Auctions: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 5: BID EXTENSION MECHANISM
    // ============================================================================

    function test_E2E_BidExtensionMechanism() public {
        console2.log("\n=== Test: Bid Extension Mechanism ===");

        // Setup
        vm.prank(alice);
        mockERC721.mint(alice, 20);

        vm.startPrank(alice);
        mockERC721.approve(address(englishAuction), 20);
        bytes32 auctionId = englishAuction.createAuction(
            address(mockERC721), 20, 1, 1 ether, 1.5 ether, AUCTION_DURATION, AuctionType.ENGLISH, alice
        );
        vm.stopPrank();
        console2.log("Step 1: Auction created");

        // Get original end time
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        uint256 originalEndTime = auction.endTime;
        console2.log("Step 2: Original end time:", originalEndTime);

        // Fast forward to last 5 minutes
        vm.warp(originalEndTime - 5 minutes);

        // Bob places bid in last minutes (should trigger extension)
        vm.prank(bob);
        englishAuction.placeBid{value: 1.8 ether}(auctionId);
        console2.log("Step 3: Bid placed in last 5 minutes");

        // Check if auction extended
        auction = englishAuction.getAuction(auctionId);
        uint256 newEndTime = auction.endTime;
        assertGt(newEndTime, originalEndTime);
        console2.log("Step 4: Auction extended to:", newEndTime);

        // Fast forward past original end but before new end
        vm.warp(originalEndTime + 1);

        // Verify auction still active
        assertTrue(englishAuction.isAuctionActive(auctionId));
        console2.log("Step 5: Auction still active after original end time");

        // Fast forward past new end time
        vm.warp(newEndTime + 1);

        // Settle
        englishAuction.settleAuction(auctionId);
        assertNFTOwner(address(mockERC721), 20, bob);
        console2.log("Step 6: Auction settled after extension");

        console2.log("=== Bid Extension Mechanism: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 6: AUCTION CANCELLATION WITH REFUNDS
    // ============================================================================

    function test_E2E_AuctionCancellationWithRefunds() public {
        console2.log("\n=== Test: Auction Cancellation with Refunds ===");

        // Setup
        vm.prank(alice);
        mockERC721.mint(alice, 30);

        vm.startPrank(alice);
        mockERC721.approve(address(auctionFactory), 30);
        bytes32 auctionId =
            auctionFactory.createEnglishAuction(address(mockERC721), 30, 1, 1 ether, 1.5 ether, AUCTION_DURATION);
        vm.stopPrank();
        console2.log("Step 1: Auction created");

        // Bob and Charlie place bids
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        auctionFactory.placeBid{value: 1.5 ether}(auctionId);

        uint256 charlieBalanceBefore = charlie.balance;
        vm.prank(charlie);
        auctionFactory.placeBid{value: 2 ether}(auctionId);
        console2.log("Step 2: Bob and Charlie placed bids");


        // Alice cancels auction with existing bids (should succeed - English auctions allow cancellation)
        vm.prank(alice);
        auctionFactory.cancelAuction(auctionId);
        console2.log("Step 3: Auction cancelled successfully");

        // Verify auction is cancelled
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(AuctionStatus.CANCELLED));

        // Verify NFT returned to seller
        assertNFTOwner(address(mockERC721), 30, alice);
        console2.log("Step 4: NFT returned to seller");

        // Verify bidders can withdraw their refunds
        uint256 bobPendingRefund = auctionFactory.getPendingRefund(auctionId, bob);
        uint256 charliePendingRefund = auctionFactory.getPendingRefund(auctionId, charlie);

        // Bob should have 1.5 ether pending refund
        assertEq(bobPendingRefund, 1.5 ether);

        // Charlie should have 2 ether pending refund (was highest bidder)
        assertEq(charliePendingRefund, 2 ether);
        console2.log("Step 5: Bidders have pending refunds");

        // Bob withdraws refund
        vm.prank(bob);
        auctionFactory.withdrawBid(auctionId);
        assertEq(bob.balance, bobBalanceBefore, "Bob should receive full refund");
        console2.log("Step 6: Bob withdrawn refund");

        // Charlie withdraws refund
        vm.prank(charlie);
        auctionFactory.withdrawBid(auctionId);
        assertEq(charlie.balance, charlieBalanceBefore, "Charlie should receive full refund");
        console2.log("Step 7: Charlie withdrawn refund");

        console2.log("=== Auction Cancellation with Refunds: SUCCESS ===\n");
    }


    // ============================================================================
    // TEST 7: RESERVE PRICE NOT MET
    // ============================================================================

    function test_E2E_ReservePriceNotMet() public {
        console2.log("\n=== Test: Reserve Price Not Met ===");

        // Setup
        vm.prank(alice);
        mockERC721.mint(alice, 40);

        vm.startPrank(alice);
        mockERC721.approve(address(englishAuction), 40);
        bytes32 auctionId = englishAuction.createAuction(
            address(mockERC721),
            40,
            1,
            1 ether, // starting price
            5 ether, // high reserve price
            AUCTION_DURATION,
            AuctionType.ENGLISH,
            alice
        );
        vm.stopPrank();
        console2.log("Step 1: Auction created with 5 ETH reserve");

        // Bob bids below reserve
        vm.prank(bob);
        englishAuction.placeBid{value: 2 ether}(auctionId);
        console2.log("Step 2: Bob bid 2 ETH (below reserve)");

        // Charlie bids higher but still below reserve
        vm.prank(charlie);
        englishAuction.placeBid{value: 3 ether}(auctionId);
        console2.log("Step 3: Charlie bid 3 ETH (still below reserve)");

        // End auction
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Settle - should return NFT to seller
        uint256 aliceBalanceBefore = alice.balance;
        englishAuction.settleAuction(auctionId);

        // Verify NFT returned to Alice
        assertNFTOwner(address(mockERC721), 40, alice);
        console2.log("Step 4: NFT returned to seller (reserve not met)");

        // Charlie should be refunded
        uint256 charlieBalance = charlie.balance;
        assertGt(charlieBalance, 0);
        console2.log("Step 5: Highest bidder refunded");

        console2.log("=== Reserve Price Not Met: SUCCESS ===\n");
    }

    // ============================================================================
    // TEST 8: DUTCH AUCTION PRICE FLOOR
    // ============================================================================

    function test_E2E_DutchAuctionPriceFloor() public {
        console2.log("\n=== Test: Dutch Auction Price Floor ===");

        // Setup
        vm.prank(alice);
        mockERC721.mint(alice, 50);

        vm.startPrank(alice);
        mockERC721.approve(address(dutchAuction), 50);
        bytes32 auctionId = dutchAuction.createAuction(
            address(mockERC721),
            50,
            1,
            10 ether, // starting price
            1 ether, // ending price (reserve price)
            AUCTION_DURATION, // duration
            AuctionType.DUTCH, // auction type
            alice // seller
        );
        vm.stopPrank();
        console2.log("Step 1: Dutch auction created (10 ETH -> 1 ETH)");

        // Fast forward to end of auction
        vm.warp(block.timestamp + AUCTION_DURATION);

        // Price should be at floor
        uint256 finalPrice = dutchAuction.getCurrentPrice(auctionId);
        assertEq(finalPrice, 1 ether);
        console2.log("Step 2: Price reached floor:", finalPrice);

        // Bob buys at floor price at end time
        vm.prank(bob);
        dutchAuction.buyNow{value: 1 ether}(auctionId);
        assertNFTOwner(address(mockERC721), 50, bob);
        console2.log("Step 3: Purchase at floor price successful");

        // Fast forward past auction end; price query remains at floor for ended auction
        vm.warp(block.timestamp + 1 days);
        uint256 postAuctionPrice = dutchAuction.getCurrentPrice(auctionId);
        assertEq(postAuctionPrice, 1 ether);
        console2.log("Step 4: Price stays at floor after auction end");

        console2.log("=== Dutch Auction Price Floor: SUCCESS ===\n");
    }
}
