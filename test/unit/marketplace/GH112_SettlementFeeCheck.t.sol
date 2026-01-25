// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/auction/EnglishAuction.sol";
import "src/core/factory/AuctionFactory.sol";
import "src/core/proxy/EnglishAuctionImplementation.sol";
import "src/core/proxy/DutchAuctionImplementation.sol";
import "src/types/AuctionTypes.sol";
import "test/mocks/MockERC721.sol";

/**
 * @title GH-112 Settlement Fee Distribution Check
 * @notice Tests to check if marketplace fees are incorrectly distributed during settlement
 * @dev Hypothesis: Fees might be distributed from auction balance, affecting refunds
 */
contract GH112_SettlementFeeCheck is Test {
    AuctionFactory public auctionFactory;
    MockERC721 public mockERC721;

    address public constant MARKETPLACE_WALLET = address(0x99999);
    address public constant SELLER = address(0xAAAAA);
    address public constant BIDDER = address(0xBBBBB);

    uint256 public constant START_PRICE = 1 ether;
    uint256 public constant DURATION = 1 days;

    function setUp() public {
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();
        auctionFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));

        mockERC721.mint(SELLER, 1);
        vm.deal(BIDDER, 10 ether);
    }

    /**
     * @notice Test: Check if settlement distributes fees from auction balance
     * @dev This could cause refund issues if auction balance is reduced
     */
    function test_GH112_Settlement_DoesNotAffectPendingRefunds() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        address auctionContract = auctionFactory.auctionToContract(auctionId);

        // Two users bid
        address BIDDER2 = address(0xCCCC);
        vm.deal(BIDDER2, 10 ether);

        vm.prank(BIDDER);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 4 ether}(auctionId);

        console.log("\n=== AFTER BIDS ===");
        console.log("Auction contract balance:", auctionContract.balance);
        console.log("BIDDER pending refund:", auctionFactory.getPendingRefund(auctionId, BIDDER));
        console.log("BIDDER2 pending refund:", auctionFactory.getPendingRefund(auctionId, BIDDER2));

        // Fast forward to end of auction
        vm.warp(block.timestamp + DURATION + 1);

        // Record balances before settlement
        uint256 marketplaceBefore = MARKETPLACE_WALLET.balance;
        uint256 sellerBefore = SELLER.balance;
        uint256 auctionBefore = auctionContract.balance;

        // Settle auction
        auctionFactory.settleAuction(auctionId);

        uint256 marketplaceAfter = MARKETPLACE_WALLET.balance;
        uint256 sellerAfter = SELLER.balance;
        uint256 auctionAfter = auctionContract.balance;

        console.log("\n=== AFTER SETTLEMENT ===");
        console.log("Marketplace wallet received:", marketplaceAfter - marketplaceBefore);
        console.log("Seller received:", sellerAfter - sellerBefore);
        // Use safe subtraction for auction balance (it decreased after settlement)
        uint256 balanceChange = auctionAfter >= auctionBefore
            ? auctionAfter - auctionBefore
            : auctionBefore - auctionAfter;
        console.log("Auction contract balance decreased by:", balanceChange);
        console.log("BIDDER pending refund:", auctionFactory.getPendingRefund(auctionId, BIDDER));
        console.log("BIDDER2 pending refund:", auctionFactory.getPendingRefund(auctionId, BIDDER2));

        // BIDDER should still be able to withdraw their refund
        uint256 b1BalanceBefore = BIDDER.balance;
        vm.prank(BIDDER);
        auctionFactory.withdrawBid(auctionId);
        uint256 b1BalanceAfter = BIDDER.balance;

        console.log("\n=== BIDDER WITHDRAWAL ===");
        console.log("Withdrawn:", b1BalanceAfter - b1BalanceBefore);
        console.log("Expected: 3 ETH");

        assertEq(b1BalanceAfter - b1BalanceBefore, 3 ether, "BIDDER should get full refund");
    }

    /**
     * @notice Test: Verify highestBidder doesn't get a refund (they won the auction)
     */
    function test_GH112_Winner_NoRefund() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // Bid
        vm.prank(BIDDER);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        // Fast forward
        vm.warp(block.timestamp + DURATION + 1);

        // Settle
        auctionFactory.settleAuction(auctionId);

        // Winner should have no refund
        uint256 pendingRefund = auctionFactory.getPendingRefund(auctionId, BIDDER);
        console.log("Winner's pending refund:", pendingRefund);
        console.log("Expected: 0 (winner pays for NFT, no refund)");

        assertEq(pendingRefund, 0, "Winner should have no refund to withdraw");
    }

    // Allow contract to receive royalty payments
    receive() external payable {}
}
