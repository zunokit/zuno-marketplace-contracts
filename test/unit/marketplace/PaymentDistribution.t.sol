// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/exchange/ERC721NFTExchange.sol";
import "src/core/exchange/ERC1155NFTExchange.sol";
import "src/core/auction/EnglishAuction.sol";
import "src/core/auction/DutchAuction.sol";
import "src/core/factory/AuctionFactory.sol";
import "src/core/proxy/EnglishAuctionImplementation.sol";
import "src/core/proxy/DutchAuctionImplementation.sol";
import "src/common/Fee.sol";
import "test/mocks/MockERC721.sol";
import "test/mocks/MockERC1155.sol";

/**
 * @title PaymentDistribution Test
 * @notice Tests to verify payment distribution works correctly for NFT sales and auctions
 */
contract PaymentDistributionTest is Test {
    // Contracts
    ERC721NFTExchange public erc721Exchange;
    ERC1155NFTExchange public erc1155Exchange;
    AuctionFactory public auctionFactory;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;

    // Test addresses
    address public constant MARKETPLACE_WALLET = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BUYER = address(0x3);
    address public constant BIDDER1 = address(0x4);
    address public constant BIDDER2 = address(0x5);
    address public constant ROYALTY_RECEIVER = address(0x6);

    // Constants
    uint256 public constant TAKER_FEE_BPS = 200; // 2%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant DEFAULT_PRICE = 1 ether;
    uint256 public constant DEFAULT_DURATION = 1 days;

    event PaymentReceived(address indexed from, uint256 amount);

    function setUp() public {
        // Deploy mock NFT contracts
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test NFT", "TNFT");

        // Deploy exchange contracts
        erc721Exchange = new ERC721NFTExchange();
        erc721Exchange.initialize(MARKETPLACE_WALLET, address(this));
        erc1155Exchange = new ERC1155NFTExchange();
        erc1155Exchange.initialize(MARKETPLACE_WALLET, address(this));

        // Deploy auction factory
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();
        auctionFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));

        // Mint test NFTs
        vm.startPrank(address(this)); // MockERC721 has onlyOwner modifier
        mockERC721.mint(SELLER, 1);
        mockERC721.mint(SELLER, 2);
        vm.stopPrank();

        mockERC1155.mint(SELLER, 1, 10);
        mockERC1155.mint(SELLER, 2, 10);

        // Give test accounts some ETH
        vm.deal(BUYER, 10 ether);
        vm.deal(BIDDER1, 10 ether);
        vm.deal(BIDDER2, 10 ether);
        vm.deal(SELLER, 1 ether);
    }

    // ============================================================================
    // ERC721 EXCHANGE PAYMENT TESTS
    // ============================================================================

    function test_ERC721_BuyNFT_SellerReceivesCorrectPayment() public {
        // Setup listing
        vm.startPrank(SELLER);
        mockERC721.approve(address(erc721Exchange), 1);
        bytes32 listingId = erc721Exchange.getGeneratedListingId(address(mockERC721), 1, SELLER);
        erc721Exchange.listNFT(address(mockERC721), 1, DEFAULT_PRICE, DEFAULT_DURATION);
        vm.stopPrank();

        // Record initial balances
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        // Calculate expected payments
        uint256 takerFee = (DEFAULT_PRICE * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = (DEFAULT_PRICE * 500) / BPS_DENOMINATOR; // 5% royalty from MockERC721
        uint256 totalPrice = DEFAULT_PRICE + takerFee + royaltyFee;

        // Buy NFT
        vm.prank(BUYER);
        erc721Exchange.buyNFT{value: totalPrice}(listingId);

        // Verify seller received correct payment (listing price minus royalty)
        uint256 expectedSellerAmount = DEFAULT_PRICE - royaltyFee;
        assertEq(
            SELLER.balance,
            sellerBalanceBefore + expectedSellerAmount,
            "Seller should receive listing price minus royalty"
        );

        // Verify marketplace received fee
        assertEq(
            MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + takerFee, "Marketplace should receive taker fee"
        );

        // Verify NFT ownership transferred
        assertEq(mockERC721.ownerOf(1), BUYER);
    }

    function test_ERC721_BuyNFT_WithRoyalty_PaymentsDistributedCorrectly() public {
        // Ensure ERC2981 default royalty does not interfere
        vm.prank(address(this));
        mockERC721.setDefaultRoyalty(address(this), 0);
        // Setup royalty via Fee contract (not ERC2981)
        vm.prank(address(this));
        Fee feeContract = mockERC721.getFeeContract();
        feeContract.setRoyaltyFee(1000); // 10% royalty (1000 basis points)

        // Setup listing
        vm.startPrank(SELLER);
        mockERC721.approve(address(erc721Exchange), 1);
        bytes32 listingId = erc721Exchange.getGeneratedListingId(address(mockERC721), 1, SELLER);
        erc721Exchange.listNFT(address(mockERC721), 1, DEFAULT_PRICE, DEFAULT_DURATION);
        vm.stopPrank();

        // Record initial balances
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;
        // Royalty goes to Fee contract owner (which is address(this))
        uint256 royaltyReceiverBalanceBefore = address(this).balance;

        // Calculate expected payments
        uint256 royalty = (DEFAULT_PRICE * 1000) / BPS_DENOMINATOR; // 10%
        uint256 takerFee = (DEFAULT_PRICE * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 totalPrice = DEFAULT_PRICE + royalty + takerFee;

        // Buy NFT
        vm.prank(BUYER);
        erc721Exchange.buyNFT{value: totalPrice}(listingId);

        // Verify all payments distributed correctly
        // Seller receives listing price minus royalty (since royalty is deducted from seller's payment)
        assertEq(
            SELLER.balance,
            sellerBalanceBefore + (DEFAULT_PRICE - royalty),
            "Seller should receive listing price minus royalty"
        );
        assertEq(
            MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + takerFee, "Marketplace should receive taker fee"
        );
        assertEq(
            address(this).balance, royaltyReceiverBalanceBefore + royalty, "Royalty receiver should receive royalty"
        );
    }

    // ============================================================================
    // ERC1155 EXCHANGE PAYMENT TESTS
    // ============================================================================

    function test_ERC1155_BuyNFT_SellerReceivesCorrectPayment() public {
        // Setup listing
        vm.startPrank(SELLER);
        mockERC1155.setApprovalForAll(address(erc1155Exchange), true);
        bytes32 listingId = erc1155Exchange.getGeneratedListingId(address(mockERC1155), 1, SELLER);
        erc1155Exchange.listNFT(address(mockERC1155), 1, 5, DEFAULT_PRICE, DEFAULT_DURATION);
        vm.stopPrank();

        // Record initial balances
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        // Calculate expected payments
        uint256 takerFee = (DEFAULT_PRICE * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = (DEFAULT_PRICE * 500) / BPS_DENOMINATOR; // 5% royalty from MockERC1155
        uint256 totalPrice = DEFAULT_PRICE + takerFee + royaltyFee;

        // Buy NFT
        vm.prank(BUYER);
        erc1155Exchange.buyNFT{value: totalPrice}(listingId);

        // Verify seller received correct payment (listing price minus royalty)
        uint256 expectedSellerAmount = DEFAULT_PRICE - royaltyFee;
        assertEq(
            SELLER.balance,
            sellerBalanceBefore + expectedSellerAmount,
            "Seller should receive listing price minus royalty"
        );

        // Verify marketplace received fee
        assertEq(
            MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + takerFee, "Marketplace should receive taker fee"
        );

        // Verify NFT ownership transferred
        assertEq(mockERC1155.balanceOf(BUYER, 1), 5);
    }

    // ============================================================================
    // AUCTION PAYMENT TESTS
    // ============================================================================

    function test_EnglishAuction_Settlement_SellerReceivesCorrectPayment() public {
        // Set royalty to 0% for this test to match expected calculations
        mockERC721.setDefaultRoyalty(SELLER, 0);

        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721),
            1,
            1,
            DEFAULT_PRICE,
            0, // No reserve
            DEFAULT_DURATION
        );
        vm.stopPrank();

        // Place winning bid
        uint256 winningBid = DEFAULT_PRICE + 0.5 ether;
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: winningBid}(auctionId);

        // Record balances before settlement
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        // Fast forward to end auction
        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        // Settle auction
        auctionFactory.settleAuction(auctionId);

        // Calculate expected payments
        uint256 marketplaceFee = (winningBid * 200) / BPS_DENOMINATOR; // 2% marketplace fee
        uint256 expectedSellerAmount = winningBid - marketplaceFee;

        // Verify payments
        assertEq(
            SELLER.balance,
            sellerBalanceBefore + expectedSellerAmount,
            "Seller should receive correct amount after fees"
        );
        assertEq(
            MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + marketplaceFee, "Marketplace should receive fee"
        );

        // Verify NFT ownership
        assertEq(mockERC721.ownerOf(1), BIDDER1);
    }

    // ============================================================================
    // MULTIPLE BIDDING TESTS
    // ============================================================================

    function test_EnglishAuction_MultipleBidsFromSameUser_RefundsAccumulate() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId =
            auctionFactory.createEnglishAuction(address(mockERC721), 1, 1, DEFAULT_PRICE, 0, DEFAULT_DURATION);
        vm.stopPrank();

        // BIDDER1 places first bid
        uint256 firstBid = DEFAULT_PRICE;
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: firstBid}(auctionId);

        // BIDDER2 outbids BIDDER1
        uint256 secondBid = firstBid + 0.1 ether;
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: secondBid}(auctionId);

        // BIDDER1 bids again (higher)
        uint256 thirdBid = secondBid + 0.1 ether;
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: thirdBid}(auctionId);

        // BIDDER2 bids again (even higher)
        uint256 fourthBid = thirdBid + 0.1 ether;
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: fourthBid}(auctionId);

        // UPDATED: With the fix, refunds ACCUMULATE instead of being cleared
        // Check pending refunds for BIDDER1 and BIDDER2
        uint256 bidder1Refund = auctionFactory.getPendingRefund(auctionId, BIDDER1);
        uint256 bidder2Refund = auctionFactory.getPendingRefund(auctionId, BIDDER2);

        // BIDDER1 was outbid twice (1 ETH + 1.2 ETH = 2.2 ETH total)
        assertEq(bidder1Refund, DEFAULT_PRICE + thirdBid); // 1 + 1.2 = 2.2

        // BIDDER2 was outbid once at 1.3 ETH, so refund = 1.1 ETH
        assertEq(bidder2Refund, secondBid); // 1.1 ETH

        // Withdraw refunds
        uint256 bidder1BalanceBefore = BIDDER1.balance;
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);
        assertEq(BIDDER1.balance, bidder1BalanceBefore + bidder1Refund);
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }
}
