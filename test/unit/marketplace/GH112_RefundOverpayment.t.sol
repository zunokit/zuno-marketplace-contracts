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
 * @title GH-112 Refund Accumulation Verification
 * @notice Tests to verify users get correct refunds (not overpayment)
 * @dev Issue #112: Users were LOSING ETH when they got outbid and bid again
 *       Previous bug: Refunds were cleared when user bid again
 *       Fix: Refunds accumulate and are only cleared for winner during settlement
 */
contract GH112_RefundOverpaymentTest is Test {
    AuctionFactory public auctionFactory;
    MockERC721 public mockERC721;

    address public constant MARKETPLACE_WALLET = address(0x9999);
    address public constant SELLER = address(0xAAAA);
    address public constant BIDDER = address(0xBBBB);

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
     * @notice Test: User bids 3 ETH, cancels, gets exactly 3 ETH back (no more, no less)
     * @dev This verifies the fix for GH-112 refund accumulation
     */
    function test_GH112_SingleBid_RefundEqualsBid() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // Record balance AFTER bid
        vm.prank(BIDDER);
        uint256 bidAmount = 3 ether;
        auctionFactory.placeBid{value: bidAmount}(auctionId);

        uint256 balanceAfterBid = BIDDER.balance;

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Verify pending refund equals bid amount
        uint256 pendingRefund = auctionFactory.getPendingRefund(auctionId, BIDDER);
        assertEq(pendingRefund, bidAmount, "Pending refund should equal bid amount");

        // Withdraw and verify
        vm.prank(BIDDER);
        auctionFactory.withdrawBid(auctionId);

        uint256 balanceAfterWithdraw = BIDDER.balance;
        uint256 actualRefund = balanceAfterWithdraw - balanceAfterBid;

        // User should receive EXACTLY what they bid (no more, no less)
        assertEq(actualRefund, bidAmount, "User should receive exactly their bid amount as refund");
        assertEq(BIDDER.balance, 10 ether, "User should have original balance back");
    }

    /**
     * @notice Test: Multiple bidders get correct total refunds
     */
    function test_GH112_MultipleBidders_TotalRefundsEqualTotalBids() public {
        address BIDDER2 = address(0x4);
        address BIDDER3 = address(0x5);
        vm.deal(BIDDER2, 10 ether);
        vm.deal(BIDDER3, 10 ether);

        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // Three users bid: 3 ETH + 3 ETH + 4 ETH = 10 ETH total
        vm.prank(BIDDER);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.placeBid{value: 4 ether}(auctionId);

        // Record balances AFTER all bids
        uint256 b1AfterBid = BIDDER.balance;
        uint256 b2AfterBid = BIDDER2.balance;
        uint256 b3AfterBid = BIDDER3.balance;

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Verify refunds
        uint256 refund1 = auctionFactory.getPendingRefund(auctionId, BIDDER);
        uint256 refund2 = auctionFactory.getPendingRefund(auctionId, BIDDER2);
        uint256 refund3 = auctionFactory.getPendingRefund(auctionId, BIDDER3);

        assertEq(refund1, 3 ether, "BIDDER refund should be 3 ETH");
        assertEq(refund2, 3 ether, "BIDDER2 refund should be 3 ETH");
        assertEq(refund3, 4 ether, "BIDDER3 refund should be 4 ETH");

        // All withdraw
        vm.prank(BIDDER);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.withdrawBid(auctionId);

        // Verify totals - total refunds should equal total bids (10 ETH)
        uint256 totalRefunded = (BIDDER.balance - b1AfterBid)
            + (BIDDER2.balance - b2AfterBid)
            + (BIDDER3.balance - b3AfterBid);

        assertEq(totalRefunded, 10 ether, "Total refunds should equal total bids (10 ETH)");
    }

    /**
     * @notice Debug: Verify marketplace fee is NOT distributed during bid placement
     */
    function test_GH112_Debug_NoFeeDuringBid() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        address auctionContract = auctionFactory.auctionToContract(auctionId);
        EnglishAuction auction = EnglishAuction(auctionContract);

        uint256 marketplaceBefore = MARKETPLACE_WALLET.balance;
        uint256 auctionBefore = auctionContract.balance;

        console.log("\n=== DEBUG: MARKETPLACE FEE CHECK ===");
        console.log("Marketplace fee rate:", auction.marketplaceFee());
        console.log("Marketplace wallet before bid:", marketplaceBefore);
        console.log("Auction contract before bid:", auctionBefore);

        // Place bid
        vm.prank(BIDDER);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        // Check if fees were distributed (they should NOT be)
        uint256 marketplaceAfter = MARKETPLACE_WALLET.balance;
        uint256 auctionAfter = auctionContract.balance;

        console.log("Marketplace wallet after bid:", marketplaceAfter);
        console.log("Auction contract after bid:", auctionAfter);
        console.log("Marketplace fee received:", marketplaceAfter - marketplaceBefore);
        console.log("Auction contract received:", auctionAfter - auctionBefore);

        // Fees should NOT be distributed during bid placement
        assertEq(marketplaceAfter - marketplaceBefore, 0, "No marketplace fee during bid");
        assertEq(auctionAfter - auctionBefore, 3 ether, "Full bid amount goes to auction contract");

        console.log("\nCORRECT: Fees are NOT distributed during bid placement");
        console.log("Fees are only distributed during settlement");
    }

    // Allow contract to receive royalty payments
    receive() external payable {}
}
