// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1155NFTExchange} from "src/core/exchange/ERC1155NFTExchange.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import "src/errors/NFTExchangeErrors.sol";
import "src/events/NFTExchangeEvents.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Fee} from "src/common/Fee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IFee {
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
    function owner() external view returns (address);
}

contract ERC1155NFTExchangeTest is Test, IERC1155Receiver {
    ERC1155NFTExchange public exchange;
    MockERC1155 public nftContract;
    address public owner = address(this);
    address public buyer = address(0x456);
    address public marketplaceWallet = address(0x789);
    uint256 constant TAKER_FEE_BPS = 200; // 2%
    uint256 constant BPS_DENOMINATOR = 10000;

    // Add receive function to make the contract payable
    receive() external payable {}

    // Add fallback function to handle ETH transfers
    fallback() external payable {}

    function setUp() public {
        exchange = new ERC1155NFTExchange();
        exchange.initialize(marketplaceWallet, address(this));
        nftContract = new MockERC1155("MockNFT", "MNFT");
        nftContract.mint(address(this), 1, 10);
        nftContract.mint(address(this), 2, 5);
        nftContract.mint(address(this), 3, 3);
    }

    // Implement IERC1155Receiver interface
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4) external pure override returns (bool) {
        return true;
    }

    // Test 1: List a single ERC-1155 NFT
    function test_ListNFT() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;

        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(listingId, address(nftContract), tokenId, owner, price);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
    }

    // Test 2: Batch list ERC-1155 NFTs
    function test_BatchListNFT() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2;
        amounts[1] = 3;
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
        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, duration);
    }

    // Test 3: Buy a single ERC-1155 NFT
    function test_BuyNFT() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: realityPrice}(listingId);
        assertEq(nftContract.balanceOf(buyer, tokenId), amount);
    }

    // Test 4: Buy ERC-1155 NFT with insufficient payment
    function test_BuyNFT_InsufficientPayment() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

        // Get the actual price including royalties and fees
        uint256 realityPrice = exchange.getBuyerSeesPrice(listingId);
        vm.deal(buyer, realityPrice);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__InsufficientPayment.selector);
        exchange.buyNFT{value: realityPrice - 0.5 ether}(listingId);
    }

    // Test 5: Buy ERC-1155 NFT with expired listing
    function test_BuyNFT_ExpiredListing() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

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
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

        emit ListingCancelled(listingId, address(nftContract), tokenId, owner);
        exchange.cancelListing(listingId);
    }

    // Test 7: Cancel listing by non-owner
    function test_CancelListing_NotOwner() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

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
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2;
        amounts[1] = 3;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, duration);

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), 2, owner);

        emit ListingCancelled(listingIds[0], address(nftContract), 1, owner);
        emit ListingCancelled(listingIds[1], address(nftContract), 2, owner);
        exchange.batchCancelListing(listingIds);
    }

    // Test 9: Batch cancel listings by non-owner
    function test_BatchCancelListing_NotOwner() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2;
        amounts[1] = 3;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;
        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, duration);

        bytes32[] memory listingIds = new bytes32[](2);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        listingIds[1] = exchange.getGeneratedListingId(address(nftContract), 2, owner);

        vm.prank(buyer);
        vm.expectRevert(NFTExchange__NotTheOwner.selector);
        exchange.batchCancelListing(listingIds);
    }

    // Test 10: Batch buy ERC-1155 NFTs
    function test_BatchBuyNFT() public {
        // List multiple NFTs
        bytes32[] memory listingIds = new bytes32[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        uint256 totalPrice = 0;

        // First NFT
        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;
        totalPrice += prices[0] * amounts[0];

        // Second NFT
        tokenIds[1] = 2;
        amounts[1] = 1;
        prices[1] = 2 ether;
        totalPrice += prices[1] * amounts[1];

        // Create listings
        for (uint256 i = 0; i < 2; i++) {
            nftContract.setApprovalForAll(address(exchange), true);
            exchange.listNFT(address(nftContract), tokenIds[i], amounts[i], prices[i], 1 days);
            listingIds[i] = exchange.getGeneratedListingId(address(nftContract), tokenIds[i], owner);
        }

        // Calculate total price including fees
        uint256 totalWithFees = exchange.getBuyerSeesPrice(listingIds[0]) + exchange.getBuyerSeesPrice(listingIds[1]);

        // Buy NFTs with correct payment
        vm.deal(buyer, totalWithFees);
        vm.deal(address(this), totalWithFees); // Give the test contract enough ETH to receive payments
        vm.prank(buyer);
        exchange.batchBuyNFT{value: totalWithFees}(listingIds);

        // Verify NFT transfers
        assertEq(nftContract.balanceOf(buyer, 1), 2);
        assertEq(nftContract.balanceOf(buyer, 2), 1);
        assertEq(nftContract.balanceOf(owner, 1), 8); // 10 - 2
        assertEq(nftContract.balanceOf(owner, 2), 4); // 5 - 1
    }

    // Test 11: Batch buy ERC-1155 NFTs with insufficient payment
    function test_BatchBuyNFT_InsufficientPayment() public {
        // List multiple NFTs
        bytes32[] memory listingIds = new bytes32[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        uint256 totalPrice = 0;

        // First NFT
        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;
        totalPrice += prices[0] * amounts[0];

        // Second NFT
        tokenIds[1] = 2;
        amounts[1] = 1;
        prices[1] = 2 ether;
        totalPrice += prices[1] * amounts[1];

        // Create listings
        for (uint256 i = 0; i < 2; i++) {
            nftContract.setApprovalForAll(address(exchange), true);
            exchange.listNFT(address(nftContract), tokenIds[i], amounts[i], prices[i], 1 days);
            listingIds[i] = exchange.getGeneratedListingId(address(nftContract), tokenIds[i], owner);
        }

        // Calculate total price including fees
        uint256 totalWithFees = exchange.getBuyerSeesPrice(listingIds[0]) + exchange.getBuyerSeesPrice(listingIds[1]);

        // Try to buy with insufficient payment (send 1 wei less than required)
        vm.deal(buyer, totalWithFees - 1);
        vm.deal(address(this), totalWithFees); // Give the test contract enough ETH to receive payments
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(NFTExchange__InsufficientPayment.selector));
        exchange.batchBuyNFT{value: totalWithFees - 1}(listingIds);
    }

    // Test 12: Batch buy ERC-1155 NFTs from mixed collections
    function test_BatchBuyNFT_MixedCollections() public {
        MockERC1155 nftContract2 = new MockERC1155("MockNFT2", "MNFT2");
        nftContract2.mint(owner, 4, 5);

        nftContract.setApprovalForAll(address(exchange), true);
        nftContract2.setApprovalForAll(address(exchange), true);

        exchange.listNFT(address(nftContract), 1, 2, 1 ether, 1 days);
        exchange.listNFT(address(nftContract2), 4, 3, 2 ether, 1 days);

        bytes32 listingId1 = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        bytes32 listingId2 = exchange.getGeneratedListingId(address(nftContract2), 4, owner);

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

    // Test 13: List ERC-1155 NFT with zero price
    function test_ListNFT_ZeroPrice() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 0;
        uint256 duration = 1 days;
        vm.expectRevert(NFTExchange__PriceMustBeGreaterThanZero.selector);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
    }

    // Test 14: List ERC-1155 NFT with zero duration
    function test_ListNFT_ZeroDuration() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 0;
        vm.expectRevert(NFTExchange__DurationMustBeGreaterThanZero.selector);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
    }

    // Test 15: List ERC-1155 NFT with zero amount
    function test_ListNFT_ZeroAmount() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 0;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        vm.expectRevert(NFTExchange__AmountMustBeGreaterThanZero.selector);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
    }

    // Test 16: List ERC-1155 NFT with insufficient balance
    function test_ListNFT_InsufficientBalance() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 20; // More than minted balance (10)
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        vm.expectRevert(NFTExchange__InsufficientBalance.selector);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
    }

    // Test 17: Buy ERC-1155 NFT with no active listing
    function test_BuyNFT_NoListing() public {
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), 1, owner);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.buyNFT{value: 1 ether}(listingId);
    }

    // Test 18: Cancel already cancelled listing
    function test_CancelListing_AlreadyCancelled() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);
        exchange.cancelListing(listingId);
        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.cancelListing(listingId);
    }

    // Test 19: Batch buy with empty listing array
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
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Calculate total price based on current royalty path
        uint256 totalPrice = exchange.getBuyerSeesPrice(listingIds[0]);

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        exchange.batchBuyNFT{value: totalPrice}(listingIds);

        assertEq(nftContract.balanceOf(buyer, 1), 2);
    }

    // Test 12: Batch buy with failed transfers
    function test_BatchBuyNFT_FailedTransfers() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Calculate total price manually for each listing
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            totalPrice += exchange.getBuyerSeesPrice(listingIds[i]);
        }

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

        // Disable ERC2981 default royalty so Fee fallback path is used
        vm.prank(owner);
        nftContract.setDefaultRoyalty(owner, 0);
        // Recompute total price after mocks to avoid InsufficientPayment
        totalPrice = exchange.getBuyerSeesPrice(listingIds[0]);
        // Fund buyer with the required total price to avoid OutOfFunds
        vm.deal(buyer, totalPrice);
        // Expect revert from payment distribution during batch buy
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("PaymentDistribution__TransferFailed()")));
        exchange.batchBuyNFT{value: totalPrice}(listingIds);
    }

    // Test 13: Batch cancel expired listing
    function test_BatchCancelListing_Expired() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

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
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

        bytes32[] memory listingIds = new bytes32[](1);
        listingIds[0] = exchange.getGeneratedListingId(address(nftContract), 1, owner);

        // Cancel the listing first
        exchange.cancelListing(listingIds[0]);

        vm.expectRevert(NFTExchange__NFTNotActive.selector);
        exchange.batchCancelListing(listingIds);
    }

    function test_BatchBuyNFT_MultipleItems() public {
        // Give the test contract enough ETH to receive seller payments
        vm.deal(address(this), 10 ether);

        // Use the existing nftContract which already has proper setup
        nftContract.setApprovalForAll(address(exchange), true);

        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory prices = new uint256[](2);

        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 2;
        amounts[1] = 1;
        prices[0] = 1 ether;
        prices[1] = 2 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

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
        exchange.batchBuyNFT{value: totalPrice}(listingIds);

        assertEq(nftContract.balanceOf(buyer, 1), 2);
        assertEq(nftContract.balanceOf(buyer, 2), 1);
    }

    function test_BuyNFT_WithExactPayment() public {
        // Give the test contract enough ETH to receive seller payments
        vm.deal(address(this), 10 ether);

        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;

        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        // Get the actual price including royalties and fees
        uint256 totalPrice = exchange.getBuyerSeesPrice(listingId);

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: totalPrice}(listingId);

        assertEq(nftContract.balanceOf(buyer, tokenId), amount);
    }

    function test_BatchBuyNFT_SingleItem() public {
        // Give the test contract enough ETH to receive seller payments
        vm.deal(address(this), 10 ether);

        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 2;
        prices[0] = 1 ether;

        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, 1 days);

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

        assertEq(nftContract.balanceOf(buyer, 1), 2);
    }

    // Test 32: Test update listing functionality for ERC1155
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing() public {
    //     nftContract.setApprovalForAll(address(exchange), true);
    //     uint256 tokenId = 1;
    //     uint256 amount = 2;
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         tokenId,
    //         owner
    //     );
    //     exchange.listNFT(
    //         address(nftContract),
    //         tokenId,
    //         amount,
    //         price,
    //         duration
    //     );

    //     // Update listing with new price
    //     uint256 newPrice = 2 ether;
    //     uint256 newDuration = 2 days;

    //     vm.expectEmit(true, true, true, true);
    //     emit NFTListingUpdated(
    //         listingId,
    //         address(nftContract),
    //         tokenId,
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

    // Test 33: Test update listing by non-owner for ERC1155
    // NOTE: updateListing functionality is not implemented yet
    // function test_UpdateListing_NotOwner() public {
    //     nftContract.setApprovalForAll(address(exchange), true);
    //     uint256 tokenId = 1;
    //     uint256 amount = 2;
    //     uint256 price = 1 ether;
    //     uint256 duration = 1 days;
    //     bytes32 listingId = exchange.getGeneratedListingId(
    //         address(nftContract),
    //         tokenId,
    //         owner
    //     );
    //     exchange.listNFT(
    //         address(nftContract),
    //         tokenId,
    //         amount,
    //         price,
    //         duration
    //     );

    //     vm.prank(buyer);
    //     vm.expectRevert(NFTExchange__NotTheOwner.selector);
    //     exchange.updateListing(listingId, 2 ether, 2 days);
    // }

    // Test 34: Test marketplace fee distribution for ERC1155
    function test_MarketplaceFeeDistribution() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256 tokenId = 1;
        uint256 amount = 2;
        uint256 price = 1 ether;
        uint256 duration = 1 days;
        bytes32 listingId = exchange.getGeneratedListingId(address(nftContract), tokenId, owner);
        exchange.listNFT(address(nftContract), tokenId, amount, price, duration);

        uint256 takerFee = (price * TAKER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = (price * 500) / BPS_DENOMINATOR; // 5% royalty from MockERC1155
        uint256 totalPrice = price + takerFee + royaltyFee;

        uint256 marketplaceBalanceBefore = marketplaceWallet.balance;

        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        exchange.buyNFT{value: totalPrice}(listingId);

        uint256 marketplaceBalanceAfter = marketplaceWallet.balance;
        // Marketplace should only receive the taker fee, not the full payment
        assertEq(marketplaceBalanceAfter - marketplaceBalanceBefore, takerFee);
    }

    // Test 35: Test batch list with mismatched array lengths for amounts
    function test_BatchListNFT_MismatchedAmountsArray() public {
        nftContract.setApprovalForAll(address(exchange), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](1); // Different length
        amounts[0] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 2 ether;
        uint256 duration = 1 days;

        vm.expectRevert(NFTExchange__ArrayLengthMismatch.selector);
        exchange.batchListNFT(address(nftContract), tokenIds, amounts, prices, duration);
    }

    // Test 36: Test list NFT that seller doesn't own
    function test_ListNFT_NotOwner() public {
        address notOwner = makeAddr("notOwner");
        nftContract.setApprovalForAll(address(exchange), true);

        vm.prank(notOwner);
        vm.expectRevert(NFTExchange__InsufficientBalance.selector);
        exchange.listNFT(address(nftContract), 1, 2, 1 ether, 1 days);
    }
}

// Mock contract that fails on receive
contract MockFailingReceiver is IERC1155Receiver {
    receive() external payable {
        revert("Transfer failed");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4) external pure override returns (bool) {
        return true;
    }
}
