// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {EnglishAuction} from "src/core/auction/EnglishAuction.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import {AuctionTestHelpers} from "test/utils/auction/AuctionTestHelpers.sol";
import "src/errors/AuctionErrors.sol";

/**
 * @title EnglishAuctionTest
 * @notice Unit tests for EnglishAuction contract
 * @dev Tests all functionality of English auctions including edge cases
 */
contract EnglishAuctionTest is AuctionTestHelpers {
    // ============================================================================
    // EVENTS FOR TESTING
    // ============================================================================

    event AuctionCreated(
        bytes32 indexed auctionId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 startTime,
        uint256 endTime,
        uint8 auctionType
    );

    event BidPlaced(
        bytes32 indexed auctionId, address indexed bidder, uint256 bidAmount, uint256 timestamp, bool isWinning
    );

    event AuctionSettled(bytes32 indexed auctionId, address indexed winner, uint256 finalPrice, address indexed seller);

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        setUpAuctionTests();
    }

    /**
     * @notice Helper to create a basic English auction using standalone contract
     * @param tokenId Token ID to auction
     * @return auctionId The created auction ID
     */
    function createBasicStandaloneEnglishAuction(uint256 tokenId) internal returns (bytes32 auctionId) {
        vm.startPrank(SELLER);

        // Approve standalone contract
        mockERC721.setApprovalForAll(address(englishAuction), true);

        auctionId = englishAuction.createAuction(
            address(mockERC721),
            tokenId,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            AuctionType.ENGLISH,
            SELLER
        );

        vm.stopPrank();
        return auctionId;
    }

    // ============================================================================
    // AUCTION CREATION TESTS
    // ============================================================================

    function test_CreateEnglishAuction_Success() public {
        uint256 tokenId = 1;

        bytes32 auctionId = createEnglishAuction(
            address(mockERC721), tokenId, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        // Verify auction details using factory (since createEnglishAuction now uses factory)
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.nftContract, address(mockERC721));
        assertEq(auction.tokenId, tokenId);
        assertEq(auction.seller, SELLER);
        assertEq(auction.startPrice, DEFAULT_START_PRICE);
        assertEq(auction.reservePrice, DEFAULT_RESERVE_PRICE);
        assertEq(uint256(auction.status), uint256(AuctionStatus.ACTIVE));
        assertEq(uint256(auction.auctionType), uint256(AuctionType.ENGLISH));
        assertEq(auction.highestBidder, address(0));
        assertEq(auction.highestBid, 0);
    }

    function test_CreateEnglishAuction_RevertIfNotOwner() public {
        vm.prank(BIDDER1);
        vm.expectRevert(Auction__NotNFTOwner.selector);

        englishAuction.createAuction(
            address(mockERC721),
            1,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            AuctionType.ENGLISH,
            BIDDER1 // Wrong owner
        );
    }

    function test_CreateEnglishAuction_RevertIfNotApproved() public {
        vm.startPrank(SELLER);
        // Don't approve the auction contract

        vm.expectRevert(Auction__NFTNotApproved.selector);
        englishAuction.createAuction(
            address(mockERC721),
            1,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            AuctionType.ENGLISH,
            SELLER
        );
        vm.stopPrank();
    }

    function test_CreateEnglishAuction_RevertIfInvalidPrice() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(englishAuction), true);

        vm.expectRevert(Auction__InvalidStartPrice.selector);
        englishAuction.createAuction(
            address(mockERC721),
            1,
            1,
            0, // Invalid start price
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            AuctionType.ENGLISH,
            SELLER
        );
        vm.stopPrank();
    }

    function test_CreateEnglishAuction_RevertIfInvalidDuration() public {
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(englishAuction), true);

        vm.expectRevert(Auction__InvalidAuctionDuration.selector);
        englishAuction.createAuction(
            address(mockERC721),
            1,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            30 minutes, // Too short
            AuctionType.ENGLISH,
            SELLER
        );
        vm.stopPrank();
    }

    // ============================================================================
    // BIDDING TESTS
    // ============================================================================

    function test_PlaceBid_FirstBid_Success() public {
        bytes32 auctionId = createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        uint256 bidAmount = DEFAULT_START_PRICE;

        vm.expectEmit(true, true, false, true);
        emit BidPlaced(auctionId, BIDDER1, bidAmount, block.timestamp, true);

        placeBidAs(auctionId, BIDDER1, bidAmount);

        // Verify auction state
        assertHighestBidder(auctionId, BIDDER1);
        assertHighestBid(auctionId, bidAmount);

        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.bidCount, 1);
    }

    function test_PlaceBid_MultipleValidBids_Success() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // First bid
        uint256 firstBid = DEFAULT_START_PRICE;
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: firstBid}(auctionId);

        // Second bid (higher)
        uint256 secondBid = calculateMinNextBid(firstBid);
        vm.prank(BIDDER2);
        englishAuction.placeBid{value: secondBid}(auctionId);

        // Third bid (even higher)
        uint256 thirdBid = calculateMinNextBid(secondBid);
        vm.prank(BIDDER3);
        englishAuction.placeBid{value: thirdBid}(auctionId);

        // Verify final state using standalone contract
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        assertEq(auction.highestBidder, BIDDER3);
        assertEq(auction.highestBid, thirdBid);
        assertEq(auction.bidCount, 3);
    }

    function test_PlaceBid_RevertIfBidTooLow() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(BIDDER1);
        vm.expectRevert(Auction__BidTooLow.selector);
        englishAuction.placeBid{value: DEFAULT_START_PRICE - 1}(auctionId);
    }

    function test_PlaceBid_RevertIfInsufficientIncrement() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Place first bid
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        // Try to place bid with insufficient increment
        vm.prank(BIDDER2);
        vm.expectRevert(Auction__InsufficientBidIncrement.selector);
        englishAuction.placeBid{value: DEFAULT_START_PRICE + 0.01 ether}(auctionId);
    }

    function test_PlaceBid_RevertIfSellerBids() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(SELLER);
        vm.expectRevert(Auction__SellerCannotBid.selector);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);
    }

    function test_PlaceBid_RevertIfAuctionEnded() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Fast forward past auction end
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        vm.warp(auction.endTime + 1);

        vm.prank(BIDDER1);
        vm.expectRevert(Auction__AuctionNotActive.selector);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);
    }

    // ============================================================================
    // BID REFUND TESTS
    // ============================================================================

    function test_WithdrawBid_Success() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Place two bids
        uint256 firstBid = DEFAULT_START_PRICE;
        uint256 secondBid = calculateMinNextBid(firstBid);

        vm.prank(BIDDER1);
        englishAuction.placeBid{value: firstBid}(auctionId);
        vm.prank(BIDDER2);
        englishAuction.placeBid{value: secondBid}(auctionId);

        // Check pending refund for BIDDER1
        uint256 pendingRefund = englishAuction.getPendingRefund(auctionId, BIDDER1);
        assertEq(pendingRefund, firstBid);

        // Withdraw refund
        uint256 balanceBefore = BIDDER1.balance;
        vm.prank(BIDDER1);
        englishAuction.withdrawBid(auctionId);

        // Verify refund received
        assertEq(BIDDER1.balance, balanceBefore + firstBid);
        assertEq(englishAuction.getPendingRefund(auctionId, BIDDER1), 0);
    }

    function test_WithdrawBid_RevertIfNoBid() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(BIDDER1);
        vm.expectRevert(Auction__NoBidToRefund.selector);
        englishAuction.withdrawBid(auctionId);
    }

    // ============================================================================
    // AUCTION EXTENSION TESTS
    // ============================================================================

    function test_AuctionExtension_LastMinuteBid() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Fast forward to near auction end (within extension threshold)
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        vm.warp(auction.endTime - 3 minutes); // 3 minutes before end

        uint256 originalEndTime = auction.endTime;

        // Place bid - should extend auction
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        // Check that auction was extended
        auction = englishAuction.getAuction(auctionId);
        assertGt(auction.endTime, originalEndTime);
    }

    // ============================================================================
    // SETTLEMENT TESTS
    // ============================================================================

    function test_SettleAuction_WithWinner_Success() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);
        uint256 winningBid = DEFAULT_START_PRICE;

        // Place winning bid
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: winningBid}(auctionId);

        // Fast forward to auction end
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        vm.warp(auction.endTime + 1);

        // Record balances before settlement
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        // Settle auction
        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(auctionId, BIDDER1, winningBid, SELLER);

        englishAuction.settleAuction(auctionId);

        // Verify NFT transferred
        assertNFTOwnership(address(mockERC721), 1, BIDDER1);

        // Verify auction status
        IAuction.Auction memory settledAuction = englishAuction.getAuction(auctionId);
        assertEq(uint256(settledAuction.status), uint256(AuctionStatus.SETTLED));

        // Verify payments (seller should receive bid minus marketplace fee)
        uint256 marketplaceFee = (winningBid * 200) / 10000; // 2% fee
        assertGt(SELLER.balance, sellerBalanceBefore);
        assertEq(MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + marketplaceFee);
    }

    function test_SettleAuction_NoBids_Success() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Fast forward to auction end without any bids
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        vm.warp(auction.endTime + 1);

        // Settle auction
        englishAuction.settleAuction(auctionId);

        // Verify auction ended without winner
        IAuction.Auction memory settledAuction = englishAuction.getAuction(auctionId);
        assertEq(uint256(settledAuction.status), uint256(AuctionStatus.ENDED));

        // Verify NFT still with seller
        assertNFTOwnership(address(mockERC721), 1, SELLER);
    }

    function test_SettleAuction_ReserveNotMet_Success() public {
        uint256 tokenId = 1;
        uint256 startPrice = 1 ether;
        uint256 reservePrice = 2 ether; // Reserve higher than start

        // Create auction with reserve price higher than start
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(englishAuction), true);

        bytes32 auctionId = englishAuction.createAuction(
            address(mockERC721), tokenId, 1, startPrice, reservePrice, DEFAULT_DURATION, AuctionType.ENGLISH, SELLER
        );
        vm.stopPrank();

        // Place bid at start price but below reserve (1 ETH < 2 ETH reserve)
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: startPrice}(auctionId); // Below reserve price

        // Fast forward to auction end
        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        vm.warp(auction.endTime + 1);

        // Settle auction
        englishAuction.settleAuction(auctionId);

        // Verify auction ended without winner (reserve not met)
        IAuction.Auction memory settledAuction = englishAuction.getAuction(auctionId);
        assertEq(uint256(settledAuction.status), uint256(AuctionStatus.ENDED));

        // Verify NFT still with seller
        assertNFTOwnership(address(mockERC721), 1, SELLER);

        // Verify bidder can withdraw refund
        uint256 pendingRefund = englishAuction.getPendingRefund(auctionId, BIDDER1);
        assertEq(pendingRefund, startPrice);
    }

    function test_SettleAuction_RevertIfStillActive() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.expectRevert(Auction__AuctionStillActive.selector);
        englishAuction.settleAuction(auctionId);
    }

    // ============================================================================
    // CANCELLATION TESTS
    // ============================================================================

    function test_CancelAuction_NoBids_Success() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(SELLER);
        englishAuction.cancelAuction(auctionId);

        IAuction.Auction memory auction = englishAuction.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(AuctionStatus.CANCELLED));
    }

    function test_CancelAuction_RevertIfHasBids() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // Place a bid
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        vm.prank(SELLER);
        vm.expectRevert(Auction__CannotCancelWithBids.selector);
        englishAuction.cancelAuction(auctionId);
    }

    function test_CancelAuction_RevertIfNotSeller() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(BIDDER1);
        vm.expectRevert(Auction__NotAuctionSeller.selector);
        englishAuction.cancelAuction(auctionId);
    }

    // ============================================================================
    // VIEW FUNCTION TESTS
    // ============================================================================

    function test_GetCurrentPrice_NoBids() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        uint256 currentPrice = englishAuction.getCurrentPrice(auctionId);
        assertEq(currentPrice, DEFAULT_START_PRICE);
    }

    function test_GetCurrentPrice_WithBids() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);
        uint256 bidAmount = DEFAULT_START_PRICE + 0.5 ether;

        vm.prank(BIDDER1);
        englishAuction.placeBid{value: bidAmount}(auctionId);

        uint256 currentPrice = englishAuction.getCurrentPrice(auctionId);
        assertEq(currentPrice, bidAmount);
    }

    function test_GetMinNextBid() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        // No bids - should return start price
        uint256 minBid = englishAuction.getMinNextBid(auctionId);
        assertEq(minBid, DEFAULT_START_PRICE);

        // With bid - should return bid + increment
        vm.prank(BIDDER1);
        englishAuction.placeBid{value: DEFAULT_START_PRICE}(auctionId);
        minBid = englishAuction.getMinNextBid(auctionId);
        assertEq(minBid, calculateMinNextBid(DEFAULT_START_PRICE));
    }

    // ============================================================================
    // UNSUPPORTED FUNCTION TESTS
    // ============================================================================

    function test_BuyNow_RevertUnsupported() public {
        bytes32 auctionId = createBasicStandaloneEnglishAuction(1);

        vm.prank(BIDDER1);
        vm.expectRevert(Auction__UnsupportedAuctionType.selector);
        englishAuction.buyNow{value: DEFAULT_START_PRICE}(auctionId);
    }
}
