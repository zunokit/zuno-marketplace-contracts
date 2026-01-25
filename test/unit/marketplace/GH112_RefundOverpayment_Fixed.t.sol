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
 * @title GH-112 Refund Overpayment Bug - Corrected Test
 * @notice Tests to reproduce critical bug where users receive MORE ETH than they bid
 * @dev Issue: Users get extra ~10% ETH when withdrawing refunds after auction cancellation
 *       Pattern: extra ~10% matches marketplace fee rate (2% = 200 basis points)
 */
contract GH112_CorrectedTest is Test {
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
     * @notice Test: Verify exact refund amount after cancellation
     */
    function test_GH112_RefundAmount_AfterCancel() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // User bids exactly 3 ETH
        uint256 bidAmount = 3 ether;
        vm.prank(BIDDER);
        uint256 balanceBeforeBid = BIDDER.balance;
        auctionFactory.placeBid{value: bidAmount}(auctionId);
        uint256 balanceAfterBid = BIDDER.balance;

        console.log("=== BID PLACEMENT ===");
        console.log("Balance before bid:", balanceBeforeBid);
        console.log("Balance after bid:", balanceAfterBid);
        console.log("Actual ETH spent:", balanceBeforeBid - balanceAfterBid);

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // Check pending refund
        uint256 pendingRefund = auctionFactory.getPendingRefund(auctionId, BIDDER);
        console.log("\n=== AFTER CANCEL ===");
        console.log("Pending refund:", pendingRefund);
        console.log("Original bid:", bidAmount);
        console.log("Difference:", int256(pendingRefund) - int256(bidAmount));

        // Withdraw and measure balance change
        uint256 balanceBeforeWithdraw = BIDDER.balance;
        vm.prank(BIDDER);
        auctionFactory.withdrawBid(auctionId);
        uint256 balanceAfterWithdraw = BIDDER.balance;

        uint256 actualRefund = balanceAfterWithdraw - balanceBeforeWithdraw;

        console.log("\n=== WITHDRAWAL ===");
        console.log("Balance before withdraw:", balanceBeforeWithdraw);
        console.log("Balance after withdraw:", balanceAfterWithdraw);
        console.log("Actual refund received:", actualRefund);
        console.log("Expected refund:", bidAmount);
        console.log("Difference:", int256(actualRefund) - int256(bidAmount));

        // ASSERTION - This will FAIL if bug exists (refund > bid)
        assertLe(actualRefund, bidAmount, "CRITICAL: User received MORE than they bid!");
        assertEq(actualRefund, bidAmount, "User should receive exactly what they bid");
    }

    /**
     * @notice Test: Multiple bidders - check total refunds
     */
    function test_GH112_MultipleBidders_RefundAccuracy() public {
        address BIDDER2 = address(0xCCCC);
        address BIDDER3 = address(0xDDDD);
        vm.deal(BIDDER2, 10 ether);
        vm.deal(BIDDER3, 10 ether);

        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        // Track balances before any bids
        uint256 b1Before = BIDDER.balance;
        uint256 b2Before = BIDDER2.balance;
        uint256 b3Before = BIDDER3.balance;

        // Three users bid
        vm.prank(BIDDER);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: 3 ether}(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.placeBid{value: 4 ether}(auctionId);

        // Cancel auction
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        // All withdraw
        vm.prank(BIDDER);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER2);
        auctionFactory.withdrawBid(auctionId);

        vm.prank(BIDDER3);
        auctionFactory.withdrawBid(auctionId);

        // Verify totals
        uint256 b1After = BIDDER.balance;
        uint256 b2After = BIDDER2.balance;
        uint256 b3After = BIDDER3.balance;

        int256 b1Change = int256(b1After) - int256(b1Before);
        int256 b2Change = int256(b2After) - int256(b2Before);
        int256 b3Change = int256(b3After) - int256(b3Before);
        int256 totalChange = b1Change + b2Change + b3Change;

        console.log("\n=== FINAL RESULTS ===");
        console.log("BIDDER balance change:", b1Change);
        console.log("BIDDER2 balance change:", b2Change);
        console.log("BIDDER3 balance change:", b3Change);
        console.log("Total change:", totalChange);
        console.log("Expected: 0 (all refunds should equal bids)");

        // ASSERTION - Total should be 0 (everyone gets back what they put in)
        assertEq(totalChange, 0, "CRITICAL: Total refunds don't match total bids!");
    }

    /**
     * @notice Test: Check if marketplace fee affects refund
     */
    function test_GH112_MarketplaceFee_NotIncludedInRefund() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, START_PRICE, 0, DURATION
        );
        vm.stopPrank();

        address auctionContract = auctionFactory.auctionToContract(auctionId);
        EnglishAuction auction = EnglishAuction(auctionContract);

        uint256 marketplaceFee = auction.marketplaceFee();
        console.log("Marketplace fee rate:", marketplaceFee, "basis points");

        // User bids
        uint256 bidAmount = 3 ether;
        vm.prank(BIDDER);
        auctionFactory.placeBid{value: bidAmount}(auctionId);

        // Cancel
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);

        uint256 pendingRefund = auctionFactory.getPendingRefund(auctionId, BIDDER);

        // Calculate what refund would be if fee was incorrectly added
        uint256 wrongRefund = bidAmount + ((bidAmount * marketplaceFee) / 10000);

        console.log("\n=== FEE CHECK ===");
        console.log("Bid amount:", bidAmount);
        console.log("Pending refund:", pendingRefund);
        console.log("Wrong refund (if fee added):", wrongRefund);
        console.log("Difference from wrong:", int256(wrongRefund) - int256(pendingRefund));

        // ASSERTION - Refund should NOT include marketplace fee
        assertEq(pendingRefund, bidAmount, "Refund should equal bid amount (no fee added)");
        if (pendingRefund == wrongRefund) {
            revert("Refund should NOT include marketplace fee");
        }
    }
}
