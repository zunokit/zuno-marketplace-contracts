// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/offers/OfferManager.sol";
import "src/core/offers/escrow/OfferEscrowManager.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/core/fees/AdvancedFeeManager.sol";
import "test/utils/TestHelpers.sol";
import "test/mocks/MockERC20.sol";
import "src/errors/NFTExchangeErrors.sol";

// Import Pausable error
error EnforcedPause();

contract OfferManagerTest is Test, TestHelpers {
    OfferManager public offerManager;
    OfferEscrowManager public escrowManager;
    MarketplaceAccessControl public accessControl;
    AdvancedFeeManager public feeManager;

    address public admin = makeAddr("admin");
    address public offerer = makeAddr("offerer");
    address public seller = makeAddr("seller");
    address public collection = makeAddr("collection");
    uint256 public tokenId = 1;

    event OfferCreated(
        bytes32 indexed offerId,
        address indexed offerer,
        address indexed collection,
        uint256 tokenId,
        uint256 amount,
        OfferManager.OfferType offerType
    );

    event OfferAccepted(
        bytes32 indexed offerId, address indexed accepter, address indexed collection, uint256 tokenId, uint256 amount
    );

    event OfferCancelled(bytes32 indexed offerId, address indexed offerer, string reason);

    function setUp() public {
        // Deploy access control
        vm.startPrank(admin);
        accessControl = new MarketplaceAccessControl();

        // Deploy fee manager (mock)
        feeManager = new AdvancedFeeManager(address(accessControl), admin);

        // Deploy escrow manager
        escrowManager = new OfferEscrowManager();

        // Deploy offer manager
        offerManager = new OfferManager(address(accessControl), address(feeManager), address(escrowManager));

        // Authorize offer manager to use escrow manager
        escrowManager.authorizeCaller(address(offerManager));

        vm.stopPrank();

        // Give test accounts some ETH
        vm.deal(offerer, 100 ether);
        vm.deal(seller, 100 ether);
    }

    function testCreateNFTOffer() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Don't check the offerId since it's generated dynamically
        vm.expectEmit(false, true, true, true); // Check offerer, collection, and data
        emit OfferCreated(
            bytes32(0), // Will be generated, so we don't check this
            offerer,
            collection,
            tokenId,
            offerAmount,
            OfferManager.OfferType.NFT_OFFER
        );

        bytes32 offerId = offerManager.createNFTOffer{value: offerAmount}(
            collection,
            tokenId,
            address(0), // ETH payment
            offerAmount,
            expiration
        );

        // Verify offer was created
        (
            bytes32 storedOfferId,
            address storedOfferer,
            address storedCollection,
            uint256 storedTokenId,
            uint256 storedAmount,
            OfferManager.OfferStatus status
        ) = offerManager.nftOffers(offerId);

        (uint256 storedExpiration, uint256 createdAt, uint256 acceptedAt) = offerManager.nftOfferTiming(offerId);

        (address paymentToken, address acceptedBy) = offerManager.nftOfferDetails(offerId);

        assertEq(storedOfferId, offerId);
        assertEq(storedOfferer, offerer);
        assertEq(storedCollection, collection);
        assertEq(storedTokenId, tokenId);
        assertEq(paymentToken, address(0));
        assertEq(storedAmount, offerAmount);
        assertEq(storedExpiration, expiration);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.ACTIVE));
        assertGt(createdAt, 0);
        assertEq(acceptedAt, 0);
        assertEq(acceptedBy, address(0));

        // Verify counters
        assertEq(offerManager.totalOffersCreated(), 1);
        assertEq(offerManager.offerCounter(), 2);

        vm.stopPrank();
    }

    function testCreateCollectionOffer() public {
        uint256 offerAmount = 0.5 ether;
        uint256 quantity = 3;
        uint256 totalAmount = offerAmount * quantity;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        vm.expectEmit(false, true, true, true); // Check offerer, collection, and data
        emit OfferCreated(
            bytes32(0), // Will be generated
            offerer,
            collection,
            0, // No specific token ID for collection offers
            offerAmount,
            OfferManager.OfferType.COLLECTION_OFFER
        );

        bytes32 offerId = offerManager.createCollectionOffer{value: totalAmount}(
            collection,
            address(0), // ETH payment
            offerAmount,
            quantity,
            expiration
        );

        // Verify collection offer was created
        (
            bytes32 storedOfferId,
            address storedOfferer,
            address storedCollection,
            uint256 storedAmount,
            uint256 storedQuantity,
            OfferManager.OfferStatus status
        ) = offerManager.collectionOffers(offerId);
        assertEq(storedOfferId, offerId);
        assertEq(storedOfferer, offerer);
        assertEq(storedCollection, collection);
        assertEq(storedAmount, offerAmount);
        assertEq(storedQuantity, quantity);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.ACTIVE));

        vm.stopPrank();
    }

    function testCreateTraitOffer() public {
        uint256 offerAmount = 0.3 ether;
        uint256 quantity = 2;
        uint256 totalAmount = offerAmount * quantity;
        uint256 expiration = block.timestamp + 1 days;
        string memory traitType = "Background";
        string memory traitValue = "Blue";

        vm.startPrank(offerer);

        vm.expectEmit(false, true, true, true); // Check offerer, collection, and data
        emit OfferCreated(
            bytes32(0), // Will be generated
            offerer,
            collection,
            0, // No specific token ID for trait offers
            offerAmount,
            OfferManager.OfferType.TRAIT_OFFER
        );

        bytes32 offerId = offerManager.createTraitOffer{value: totalAmount}(
            collection,
            traitType,
            traitValue,
            address(0), // ETH payment
            offerAmount,
            quantity,
            expiration
        );

        // Verify trait offer was created
        (
            bytes32 storedOfferId,
            address storedOfferer,
            address storedCollection,
            uint256 storedAmount,
            uint256 storedQuantity,
            OfferManager.OfferStatus status
        ) = offerManager.traitOffers(offerId);
        assertEq(storedOfferId, offerId);
        assertEq(storedOfferer, offerer);
        assertEq(storedCollection, collection);
        assertEq(storedAmount, offerAmount);
        assertEq(storedQuantity, quantity);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.ACTIVE));

        vm.stopPrank();
    }

    function testCancelNFTOffer() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Create offer
        vm.startPrank(offerer);
        bytes32 offerId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        uint256 balanceBefore = offerer.balance;

        vm.expectEmit(true, true, false, true);
        emit OfferCancelled(offerId, offerer, "Cancel reason");

        // Cancel offer
        offerManager.cancelOffer(offerId, "Cancel reason");

        // Verify offer status
        (,,,,, OfferManager.OfferStatus status) = offerManager.nftOffers(offerId);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.CANCELLED));

        // Verify refund
        assertEq(offerer.balance, balanceBefore + offerAmount);

        vm.stopPrank();
    }

    function testInvalidOfferCreation() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Test invalid collection (zero address)
        vm.expectRevert(NFTExchange__InvalidCollection.selector);
        offerManager.createNFTOffer{value: offerAmount}(address(0), tokenId, address(0), offerAmount, expiration);

        // Test invalid amount (zero)
        vm.expectRevert(NFTExchange__InvalidPrice.selector);
        offerManager.createNFTOffer{value: 0}(collection, tokenId, address(0), 0, expiration);

        // Test invalid expiration (too short)
        vm.expectRevert(NFTExchange__InvalidDuration.selector);
        offerManager.createNFTOffer{value: offerAmount}(
            collection,
            tokenId,
            address(0),
            offerAmount,
            block.timestamp + 30 minutes // Less than MIN_OFFER_DURATION
        );

        // Test invalid expiration (too long)
        vm.expectRevert(NFTExchange__InvalidDuration.selector);
        offerManager.createNFTOffer{value: offerAmount}(
            collection,
            tokenId,
            address(0),
            offerAmount,
            block.timestamp + 31 days // More than MAX_OFFER_DURATION
        );

        // Test incorrect ETH amount
        vm.expectRevert(NFTExchange__InvalidPrice.selector);
        offerManager.createNFTOffer{value: 0.5 ether}(
            collection,
            tokenId,
            address(0),
            offerAmount, // 1 ether but only sent 0.5
            expiration
        );

        vm.stopPrank();
    }

    function testUnauthorizedCancellation() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Create offer as offerer
        vm.prank(offerer);
        bytes32 offerId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        // Try to cancel as different user
        vm.prank(seller);
        vm.expectRevert(NFTExchange__InvalidOwner.selector);
        offerManager.cancelOffer(offerId, "Cancel reason");
    }

    function testOfferExpiration() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 2 hours; // Must be > MIN_OFFER_DURATION (1 hour)

        // Create offer
        vm.prank(offerer);
        bytes32 offerId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        // Fast forward past expiration
        vm.warp(expiration + 1);

        // Try to accept expired offer (this would fail in acceptNFTOffer)
        // For now, we just verify the offer exists and is still marked as ACTIVE
        // The expiration check happens during acceptance
        (,,,,, OfferManager.OfferStatus status) = offerManager.nftOffers(offerId);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.ACTIVE));
    }

    function testCollectionOfferLimits() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Give offerer enough ETH for the large offer
        vm.deal(offerer, 200 ether);
        vm.startPrank(offerer);

        // Test invalid quantity (zero)
        vm.expectRevert(NFTExchange__InvalidQuantity.selector);
        offerManager.createCollectionOffer{value: 0}(
            collection,
            address(0),
            offerAmount,
            0, // Invalid quantity
            expiration
        );

        // Test invalid quantity (too high)
        vm.expectRevert(NFTExchange__InvalidQuantity.selector);
        offerManager.createCollectionOffer{value: 101 ether}(
            collection,
            address(0),
            offerAmount,
            101, // Exceeds MAX (100)
            expiration
        );

        vm.stopPrank();
    }

    function testTraitOfferLimits() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Test invalid quantity (too high for trait offers)
        vm.expectRevert(NFTExchange__InvalidQuantity.selector);
        offerManager.createTraitOffer{value: 51 ether}(
            collection,
            "Background",
            "Blue",
            address(0),
            offerAmount,
            51, // Exceeds MAX (50) for trait offers
            expiration
        );

        // Test empty trait type
        vm.expectRevert(NFTExchange__InvalidParameters.selector);
        offerManager.createTraitOffer{value: offerAmount}(
            collection,
            "", // Empty trait type
            "Blue",
            address(0),
            offerAmount,
            1,
            expiration
        );

        // Test empty trait value
        vm.expectRevert(NFTExchange__InvalidParameters.selector);
        offerManager.createTraitOffer{value: offerAmount}(
            collection,
            "Background",
            "", // Empty trait value
            address(0),
            offerAmount,
            1,
            expiration
        );

        vm.stopPrank();
    }

    function testFuzzOfferCreation(uint256 amount, uint256 duration, uint8 quantity) public {
        // Bound inputs to valid ranges
        amount = bound(amount, 0.001 ether, 100 ether);
        duration = bound(duration, 1 hours + 1, 30 days); // Must be > MIN_OFFER_DURATION
        quantity = uint8(bound(quantity, 1, 100));

        uint256 expiration = block.timestamp + duration;
        uint256 totalAmount = amount * quantity;

        // Ensure offerer has enough ETH
        vm.deal(offerer, totalAmount + 1 ether);

        vm.prank(offerer);
        bytes32 offerId = offerManager.createCollectionOffer{value: totalAmount}(
            collection, address(0), amount, quantity, expiration
        );

        // Verify offer was created successfully
        (
            bytes32 storedOfferId,
            address storedOfferer,
            address storedCollection,
            uint256 storedAmount,
            uint256 storedQuantity,
            OfferManager.OfferStatus status
        ) = offerManager.collectionOffers(offerId);
        assertEq(storedOfferId, offerId);
        assertEq(storedOfferer, offerer);
        assertEq(storedCollection, collection);
        assertEq(storedAmount, amount);
        assertEq(storedQuantity, quantity);
        assertEq(uint256(status), uint256(OfferManager.OfferStatus.ACTIVE));
    }

    // ============================================================================
    // ADDITIONAL COVERAGE TESTS
    // ============================================================================

    function testGetOffersByOfferer() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Create multiple offers
        bytes32 offerId1 =
            offerManager.createNFTOffer{value: offerAmount}(collection, 1, address(0), offerAmount, expiration);
        bytes32 offerId2 =
            offerManager.createNFTOffer{value: offerAmount}(collection, 2, address(0), offerAmount, expiration);
        bytes32 offerId3 =
            offerManager.createCollectionOffer{value: offerAmount}(collection, address(0), offerAmount, 1, expiration);

        vm.stopPrank();

        // Test getting offers by offerer
        bytes32[] memory nftOffers = offerManager.getOffersByOfferer(offerer, OfferManager.OfferType.NFT_OFFER);
        bytes32[] memory collectionOffers =
            offerManager.getOffersByOfferer(offerer, OfferManager.OfferType.COLLECTION_OFFER);

        assertEq(nftOffers.length, 2);
        assertEq(collectionOffers.length, 1);
        assertEq(nftOffers[0], offerId1);
        assertEq(nftOffers[1], offerId2);
        assertEq(collectionOffers[0], offerId3);
    }

    function testGetOffersByCollection() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;
        address collection2 = makeAddr("collection2");

        vm.startPrank(offerer);

        // Create offers for different collections
        bytes32 offerId1 =
            offerManager.createNFTOffer{value: offerAmount}(collection, 1, address(0), offerAmount, expiration);
        bytes32 offerId2 =
            offerManager.createCollectionOffer{value: offerAmount}(collection, address(0), offerAmount, 1, expiration);
        offerManager.createNFTOffer{value: offerAmount}(collection2, 1, address(0), offerAmount, expiration);

        vm.stopPrank();

        // Test getting offers by collection
        bytes32[] memory nftOffers = offerManager.getOffersByCollection(collection, OfferManager.OfferType.NFT_OFFER);
        bytes32[] memory collectionOffers =
            offerManager.getOffersByCollection(collection, OfferManager.OfferType.COLLECTION_OFFER);

        assertEq(nftOffers.length, 1);
        assertEq(collectionOffers.length, 1);
        assertEq(nftOffers[0], offerId1);
        assertEq(collectionOffers[0], offerId2);
    }

    function testGetActiveOffers() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Create offers
        bytes32 offerId1 =
            offerManager.createNFTOffer{value: offerAmount}(collection, 1, address(0), offerAmount, expiration);
        bytes32 offerId2 =
            offerManager.createNFTOffer{value: offerAmount}(collection, 2, address(0), offerAmount, expiration);

        // Cancel one offer
        offerManager.cancelOffer(offerId2, "Cancel reason");

        vm.stopPrank();

        // Test getting active offers
        bytes32[] memory activeOffers = offerManager.getActiveOffers(OfferManager.OfferType.NFT_OFFER);

        assertEq(activeOffers.length, 1);
        assertEq(activeOffers[0], offerId1);
    }

    function testOfferCounters() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Initial state
        assertEq(offerManager.totalOffersCreated(), 0);
        assertEq(offerManager.offerCounter(), 1);

        vm.startPrank(offerer);

        // Create offers
        offerManager.createNFTOffer{value: offerAmount}(collection, 1, address(0), offerAmount, expiration);
        assertEq(offerManager.totalOffersCreated(), 1);
        assertEq(offerManager.offerCounter(), 2);

        offerManager.createCollectionOffer{value: offerAmount}(collection, address(0), offerAmount, 1, expiration);
        assertEq(offerManager.totalOffersCreated(), 2);
        assertEq(offerManager.offerCounter(), 3);

        offerManager.createTraitOffer{value: offerAmount}(
            collection, "trait", "value", address(0), offerAmount, 1, expiration
        );
        assertEq(offerManager.totalOffersCreated(), 3);
        assertEq(offerManager.offerCounter(), 4);

        vm.stopPrank();
    }

    function testCancelNonExistentOffer() public {
        bytes32 nonExistentOfferId = keccak256("nonexistent");

        vm.prank(offerer);
        vm.expectRevert(NFTExchange__InvalidListing.selector);
        offerManager.cancelOffer(nonExistentOfferId, "Cancel reason");
    }

    function testCancelAlreadyCancelledOffer() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(offerer);

        // Create and cancel offer
        bytes32 offerId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);
        offerManager.cancelOffer(offerId, "Cancel reason");

        // Try to cancel again
        vm.expectRevert(NFTExchange__InvalidListing.selector);
        offerManager.cancelOffer(offerId, "Cancel reason");

        vm.stopPrank();
    }

    function testMultipleOffersFromSameUser() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        vm.deal(offerer, 10 ether);
        vm.startPrank(offerer);

        // Create multiple offers for same NFT (should be allowed)
        bytes32 offerId1 =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);
        bytes32 offerId2 =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        // Verify both offers exist and are different
        assertNotEq(offerId1, offerId2);

        (,,,,, OfferManager.OfferStatus status1) = offerManager.nftOffers(offerId1);
        (,,,,, OfferManager.OfferStatus status2) = offerManager.nftOffers(offerId2);

        assertEq(uint256(status1), uint256(OfferManager.OfferStatus.ACTIVE));
        assertEq(uint256(status2), uint256(OfferManager.OfferStatus.ACTIVE));

        vm.stopPrank();
    }

    function testOfferWithDifferentPaymentTokens() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Deploy a real MockERC20 contract
        MockERC20 mockToken = new MockERC20("TestToken", "TT", 18);

        // Mint tokens to offerer and approve OfferEscrowManager
        mockToken.mint(offerer, offerAmount);
        vm.prank(offerer);
        mockToken.approve(address(escrowManager), offerAmount);

        vm.startPrank(offerer);

        // Create offer with ETH
        bytes32 ethOfferId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        // Create offer with ERC20 token (no ETH sent)
        bytes32 tokenOfferId =
            offerManager.createNFTOffer(collection, tokenId + 1, address(mockToken), offerAmount, expiration);

        // Verify payment tokens
        (address ethPaymentToken,) = offerManager.nftOfferDetails(ethOfferId);
        (address tokenPaymentToken,) = offerManager.nftOfferDetails(tokenOfferId);

        assertEq(ethPaymentToken, address(0));
        assertEq(tokenPaymentToken, address(mockToken));

        vm.stopPrank();
    }

    function testEmergencyFunctions() public {
        uint256 offerAmount = 1 ether;
        uint256 expiration = block.timestamp + 1 days;

        // Create offer
        vm.prank(offerer);
        bytes32 offerId =
            offerManager.createNFTOffer{value: offerAmount}(collection, tokenId, address(0), offerAmount, expiration);

        // Test emergency pause (only admin can do this)
        vm.prank(admin);
        offerManager.pause();

        // Try to create offer while paused
        vm.prank(offerer);
        vm.expectRevert(EnforcedPause.selector);
        offerManager.createNFTOffer{value: offerAmount}(collection, tokenId + 1, address(0), offerAmount, expiration);

        // Unpause
        vm.prank(admin);
        offerManager.unpause();

        // Should work again
        vm.prank(offerer);
        offerManager.createNFTOffer{value: offerAmount}(collection, tokenId + 1, address(0), offerAmount, expiration);
    }
}
