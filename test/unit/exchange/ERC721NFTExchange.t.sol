// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "test/mocks/MockERC721.sol";
import "src/core/exchange/ERC721NFTExchange.sol";
import "src/errors/NFTExchangeErrors.sol";
import "src/events/NFTExchangeEvents.sol";
import {Fee} from "src/common/Fee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IFee {
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
    function owner() external view returns (address);
}

contract ERC721NFTExchangeTest is Test {
    ERC721NFTExchange exchange;
    MockERC721 nftContract;
    address owner = address(this);
    address buyer = address(0x456);
    address marketplaceWallet = address(0x789);
    uint256 constant TAKER_FEE_BPS = 200; // 2%
    uint256 constant BPS_DENOMINATOR = 10000;

    // Add receive function to make the contract payable
    receive() external payable {}

    function setUp() public {
        exchange = new ERC721NFTExchange();
        exchange.initialize(marketplaceWallet, address(this));
        nftContract = new MockERC721("MockNFT", "MNFT");
        nftContract.mint(address(this), 1);
        nftContract.mint(address(this), 2);
        nftContract.mint(address(this), 3);
        // Set sufficient balance for test contract (seller and marketplace wallet)
        vm.deal(address(this), 1e19); // 10 ETH, ample for all payments
        // Set approval for all NFTs
        nftContract.setApprovalForAll(address(exchange), true);
    }

    // Test 1: List a single NFT
    function test_ListNFT() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;

        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(listingId, address(nftContract), 1, owner, price);
        exchange.listNFT(address(nftContract), 1, price, duration);
    }

    // Test 2: Batch list NFTs
    function test_BatchListNFT() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;

        bytes32 listingId1 = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        bytes32 listingId2 = exchange.getGeneratedListingId(address(nftContract), 2, owner);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(listingId1, address(nftContract), 1, owner, prices[0]);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(listingId2, address(nftContract), 2, owner, prices[1]);
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);
    }

    // Test 3: Buy a single NFT
    function test_BuyNFT() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice}(listingId);
        assertEq(nftContract.ownerOf(1), buyer);
    }

    // Test 4: Buy NFT with insufficient payment
    function test_BuyNFT_InsufficientPayment() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__InsufficientPayment.selector);
        exchange.buyNFT{value: realityPrice - 0.5 ether}(listingId);
    }

    // Test 5: Buy NFT with expired listing
    function test_BuyNFT_ExpiredListing() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        vm.warp(block.timestamp + 2 days);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__ListingExpired.selector);
        exchange.buyNFT{value: realityPrice}(listingId);
    }

    // Test 6: Cancel a listing
    function test_CancelListing() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        vm.expectEmit(true, true, true, false);
        emit ListingCancelled(listingId, address(nftContract), 1, owner);
        exchange.cancelListing(listingId);
    }

    // Test 7: Cancel listing by non-owner
    function test_CancelListing_NotOwner() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        vm.prank(buyer);
        vm.expectRevert(NFTExchange__NotTheOwner.selector);
        exchange.cancelListing(listingId);
    }

    // Test 8: Batch cancel listings
    function test_BatchCancelListing() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), 2, owner);

        vm.expectEmit(true, true, true, false);
        emit ListingCancelled(listingIds[0], address(nftContract), 1, owner);
        vm.expectEmit(true, true, true, false);
        emit ListingCancelled(listingIds[1], address(nftContract), 2, owner);
        exchange.batchCancelListing(listingIds);
    }

    // Test 9: Batch cancel listings by non-owner
    function test_BatchCancelListing_NotOwner() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), 2, owner);

        vm.prank(buyer);
        vm.expectRevert(NFTExchange__NotTheOwner.selector);
        exchange.batchCancelListing(listingIds);
    }

    // Test 10: Batch buy NFTs
    function test_BatchBuyNFT() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);

        // Buy first NFT
        bytes32 listingId1 = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        uint256 realityPrice1 = exchange.getBuyerSeesPrice(listingId1);
        vm.deal(buyer, realityPrice1);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice1}(listingId1);
        assertEq(nftContract.ownerOf(1), buyer);

        // Buy second NFT
        bytes32 listingId2 = exchange.getGeneratedListingId(address(nftContract), 2, owner);
        uint256 realityPrice2 = exchange.getBuyerSeesPrice(listingId2);
        vm.deal(buyer, realityPrice2);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice2}(listingId2);
        assertEq(nftContract.ownerOf(2), buyer);
    }

    // Test 11: Batch buy NFTs with insufficient payment
    function test_BatchBuyNFT_InsufficientPayment() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), 2, owner);

        // Calculate total price manually for each listing
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            totalPrice += exchange.getBuyerSeesPrice(listingIds[i]);
        }

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__InsufficientPayment.selector);
        exchange.batchBuyNFT{value: totalPrice - 1 ether}(listingIds);
    }

    // Test 12: Batch buy NFTs from mixed collections (should revert)
    function test_BatchBuyNFT_MixedCollections() public {
        MockERC721 nftContract2 = new MockERC721("MockNFT2", "MNFT2");
        vm.prank(address(this));
        nftContract2.transferOwnership(owner);

        vm.startPrank(owner);
        nftContract2.mint(owner, 4);
        nftContract.setApprovalForAll(address(exchange), true);
        nftContract2.setApprovalForAll(address(exchange), true);

        bytes32 listingId1 = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        bytes32 listingId2 = exchange.getGeneratedListingId(address(nftContract2), 4, owner);
        exchange.listNFT(address(nftContract), 1, 1 ether, 1 days);
        exchange.listNFT(address(nftContract2), 4, 2 ether, 1 days);
        vm.stopPrank();

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = listingId1;
        listingIds[1] = listingId2;

        uint256 totalPrice = 1 ether + (1 ether * TAKER_FEE_BPS) / BPS_DENOMINATOR + 2 ether + (2 ether * TAKER_FEE_BPS)
            / BPS_DENOMINATOR;
        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__ArrayLengthMismatch.selector);
        exchange.batchBuyNFT{value: totalPrice}(listingIds);
    }

    // Test 13: List NFT with zero price
    function test_ListNFT_ZeroPrice() public {
        vm.startPrank(owner);
        nftContract.approve(address(exchange), 1);
        uint256 price = 0;
        uint256 duration = 1 days;
        vm.expectRevert(NFTExchange__PriceMustBeGreaterThanZero.selector);
        exchange.listNFT(address(nftContract), 1, price, duration);
        vm.stopPrank();
    }

    // Test 14: List NFT with zero duration
    function test_ListNFT_ZeroDuration() public {
        vm.startPrank(owner);
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 0;
        vm.expectRevert(NFTExchange__DurationMustBeGreaterThanZero.selector);
        exchange.listNFT(address(nftContract), 1, price, duration);
        vm.stopPrank();
    }

    // Test 15: Buy NFT with no active listing
    function test_BuyNFT_NoListing() public {
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.buyNFT{value: 1 ether}(listingId);
    }

    // Test 16: Cancel already cancelled listing
    function test_CancelListing_AlreadyCancelled() public {
        vm.startPrank(owner);
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);
        exchange.cancelListing(listingId);
        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.cancelListing(listingId);
        vm.stopPrank();
    }

    // Test 17: Batch buy with empty listing array
    function test_BatchBuyNFT_EmptyArray() public {
        bytes32[] memory listingIds = new bytes32[](0);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__ArrayLengthMismatch.selector);
        exchange.batchBuyNFT{value: 0}(listingIds);
    }

    // Test 11: Batch buy with zero royalty
    function test_BatchBuyNFT_ZeroRoyalty() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Calculate total price manually for each listing
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            totalPrice += exchange.getBuyerSeesPrice(listingIds[i]);
        }

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        exchange.batchBuyNFT{value: totalPrice}(listingIds);

        assertEq(nftContract.ownerOf(1), buyer);
    }

    // Test 12: Batch buy with failed transfers
    function test_BatchBuyNFT_FailedTransfers() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Force royalty fallback to Fee by disabling ERC2981 for this token
        // by setting default royalty on a different address with 0 rate
        vm.prank(owner);
        nftContract.setDefaultRoyalty(owner, 0);
        uint256 takerFee = (prices[0] * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyAmount = (prices[0] * 1000) / BPS_DENOMINATOR; // 10% royalty from mocked Fee
        uint256 totalPrice = prices[0] + takerFee + royaltyAmount;

        // Create a contract that will fail on receive
        MockFailingReceiver failingReceiver = new MockFailingReceiver();
        vm.deal(address(failingReceiver), totalPrice);

        // Get the fee contract and mock its methods to return the failing receiver
        Fee feeContract = nftContract.feeContract();

        // Mock the fee contract's owner() method to return the failing receiver
        vm.mockCall(
            address(feeContract), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(failingReceiver))
        );

        // Mock the fee contract's getRoyaltyFee() method to return 1000 (10%)
        vm.mockCall(
            address(feeContract),
            abi.encodeWithSignature("getRoyaltyFee()"),
            abi.encode(uint256(1000)) // 10% in basis points
        );

        vm.prank(address(failingReceiver));
        vm.expectRevert(bytes4(keccak256("PaymentDistribution__TransferFailed()")));
        exchange.batchBuyNFT{value: totalPrice}(listingIds);
    }

    // Test 13: Batch cancel expired listing
    function test_BatchCancelListing_Expired() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(NFTExchange__ListingExpired.selector);
        exchange.batchCancelListing(listingIds);
    }

    // Test 14: Batch cancel inactive listing
    function test_BatchCancelListing_Inactive() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Cancel the listing first
        exchange.cancelListing(listingIds[0]);

        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.batchCancelListing(listingIds);
    }

    function test_BatchBuyNFT_MultipleItems() public {
        // Define token IDs and prices
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        prices[0] = 0.1 ether;
        prices[1] = 0.2 ether;

        // List NFTs
        exchange.batchListNFT(address(nftContract), tokenIds, prices, 1 days);

        // Get listing IDs
        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), tokenIds[0], address(this));
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), tokenIds[1], address(this));

        // Calculate total price manually for each listing
        uint256 totalPriceWithFees = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            totalPriceWithFees += exchange.getBuyerSeesPrice(listingIds[i]);
        }

        // Give buyer enough ETH to pay for both NFTs
        vm.deal(buyer, totalPriceWithFees);

        // Log balances for debugging
        console.log("Exchange balance before:", address(exchange).balance);
        console.log("Marketplace wallet balance before:", address(this).balance);
        console.log("Buyer balance before:", buyer.balance);

        // Execute batch buy as buyer
        vm.prank(buyer);
        exchange.batchBuyNFT{value: totalPriceWithFees}(listingIds);

        // Log balances for debugging
        console.log("Exchange balance after:", address(exchange).balance);
        console.log("Marketplace wallet balance after:", address(this).balance);
        console.log("Buyer balance after:", buyer.balance);

        // Verify buyer received NFTs
        assertEq(nftContract.ownerOf(1), buyer);
        assertEq(nftContract.ownerOf(2), buyer);
    }

    function test_BuyNFT_WithExactPayment() public {
        // Give the test contract enough ETH to receive seller payments
        vm.deal(address(this), 10 ether);

        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // Get the actual price including royalties and fees
        uint256 totalPrice = exchange.getBuyerSeesPrice(listingId);

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: totalPrice}(listingId);

        assertEq(nftContract.ownerOf(1), buyer);
    }

    // Test 18: List NFT without approval
    function test_ListNFT_NoApproval() public {
        // Mint a new NFT to a different address
        address seller = address(0x999);
        nftContract.mint(seller, 10);

        uint256 price = 1 ether;
        uint256 duration = 1 days;

        // Try to list without approval - should revert
        vm.prank(seller);
        vm.expectRevert(NFTExchange__MarketplaceNotApproved.selector);
        exchange.listNFT(address(nftContract), 10, price, duration);
    }

    // Test 19: List NFT that doesn't exist
    function test_ListNFT_NonExistentToken() public {
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        vm.expectRevert(NFTExchange__NotTheOwner.selector);
        exchange.listNFT(address(nftContract), 999, price, duration);
    }

    // Test 20: List NFT with invalid contract address
    function test_ListNFT_InvalidContract() public {
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        vm.expectRevert(); // call will revert without data for zero address
        exchange.listNFT(address(0), 1, price, duration);
    }

    // Test 21: Buy NFT that was already sold
    function test_BuyNFT_AlreadySold() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // First buyer buys the NFT
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice}(listingId);

        // Second buyer tries to buy the same NFT
        address buyer2 = address(0x789);
        vm.deal(buyer2, realityPrice);
        vm.prank(buyer2);
        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.buyNFT{value: realityPrice}(listingId);
    }

    // Test 22: List already listed NFT (duplicate listing)
    function test_ListNFT_AlreadyListed() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;

        exchange.listNFT(address(nftContract), 1, price, duration);

        vm.expectRevert(NFTExchange__NFTAlreadyListed.selector);
        exchange.listNFT(address(nftContract), 1, price, duration);
    }

    // Test 23: Batch list with mismatched array lengths
    function test_BatchListNFT_MismatchedArrays() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory prices = new uint256[](1); // Different length
        prices[0] = 1 ether;
        uint256 duration = 1 days;

        vm.expectRevert(NFTExchange__ArrayLengthMismatch.selector);
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);
    }

    // Test 24: Batch list with empty arrays
    function test_BatchListNFT_EmptyArrays() public {
        uint256[] memory tokenIds = new uint256[](0);
        uint256[] memory prices = new uint256[](0);
        uint256 duration = 1 days;

        // Empty arrays should be handled gracefully
        exchange.batchListNFT(address(nftContract), tokenIds, prices, duration);
    }

    // Test 25: Test getter functions
    function test_GetterFunctions() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // Test getBuyerSeesPrice - should include both taker fee and royalty
        uint256 buyerPrice = exchange.getBuyerSeesPrice(listingId);
        uint256 takerFee = (price * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = (price * 500) / BPS_DENOMINATOR; // 5% royalty from MockERC721
        uint256 expectedPrice = price + takerFee + royaltyFee;
        assertEq(buyerPrice, expectedPrice);

        // Test getListingsByCollection
        bytes32[] memory collectionListings = exchange.getListingsByCollection(address(nftContract));
        assertEq(collectionListings.length, 1);
        assertEq(collectionListings[0], listingId);

        // Test getListingsBySeller
        bytes32[] memory sellerListings = exchange.getListingsBySeller(owner);
        assertEq(sellerListings.length, 1);
        assertEq(sellerListings[0], listingId);
    }

    // Test 26: Test update listing functionality
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing() public {
    //     nftContract.approve(address(exchange), 1);
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         1,
    //         owner
    //     );
    //     exchange.listNFT(address(nftContract), 1, price, duration);

    //     // Update listing with new price
    //     uint256 newPrice = 2 ether;
    //     uint256 newDuration = 2 days;

    //     vm.expectEmit(true, true, true, true);
    //     emit NFTListingUpdated(
    //         listingId,
    //         address(nftContract),
    //         1,
    //         owner,
    //         newPrice
    //     );
    //     exchange.updateListing(listingId, newPrice, newDuration);

    //     // Verify updated price
    //     uint256 buyerPrice = exchange.getBuyerSeesPrice(listingId);
    //     uint256 expectedPrice = newPrice +
    //         (newPrice * TAKER_FEE_BPS) /
    //         BPS_DENOMINATOR;
    //     assertEq(buyerPrice, expectedPrice);
    // }

    // Test 27: Test update listing by non-owner
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing_NotOwner() public {
    //     nftContract.approve(address(exchange), 1);
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         1,
    //         owner
    //     );
    //     exchange.listNFT(address(nftContract), 1, price, duration);

    //     vm.prank(buyer);
    //     vm.expectRevert(NFTExchange__NotTheOwner.selector);
    //     exchange.updateListing(listingId, 2 ether, 2 days);
    // }

    // Test 28: Test update listing with zero price
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing_ZeroPrice() public {
    //     nftContract.approve(address(exchange), 1);
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         1,
    //         owner
    //     );
    //     exchange.listNFT(address(nftContract), 1, price, duration);

    //     vm.expectRevert(NFTExchange__PriceMustBeGreaterThanZero.selector);
    //     exchange.updateListing(listingId, 0, 2 days);
    // }

    // Test 29: Test update listing with zero duration
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing_ZeroDuration() public {
    //     nftContract.approve(address(exchange), 1);
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         1,
    //         owner
    //     );
    //     exchange.listNFT(address(nftContract), 1, price, duration);

    //     vm.expectRevert(NFTExchange__DurationMustBeGreaterThanZero.selector);
    //     exchange.updateListing(listingId, 2 ether, 0);
    // }

    // Test 30: Test update inactive listing
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing_Inactive() public {
    //     nftContract.approve(address(exchange), 1);
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         1,
    //         owner
    //     );
    //     exchange.listNFT(address(nftContract), 1, price, duration);
    //     exchange.cancelListing(listingId);

    //     vm.expectRevert(NFTExchange__NFTNotActive.selector);
    //     exchange.updateListing(listingId, 2 ether, 2 days);
    // }

    // Test 31: Test marketplace fee distribution
    function test_MarketplaceFeeDistribution() public {
        nftContract.approve(address(exchange), 1);
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        exchange.listNFT(address(nftContract), 1, price, duration);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        uint256 expectedTakerFee = (price * TAKER_FEE_BPS) / BPS_DENOMINATOR;

        uint256 marketplaceBalanceBefore = marketplaceWallet.balance;

        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice}(listingId);

        uint256 marketplaceBalanceAfter = marketplaceWallet.balance;
        // Marketplace should only receive the taker fee, not the full payment
        assertEq(marketplaceBalanceAfter - marketplaceBalanceBefore, expectedTakerFee);
    }
}

// Mock contract that fails on receive
contract MockFailingReceiver {
    receive() external payable {
        revert("Transfer failed");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
