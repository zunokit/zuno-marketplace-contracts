// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {EnglishAuction} from "src/core/auction/EnglishAuction.sol";
import {DutchAuction} from "src/core/auction/DutchAuction.sol";
import {EnglishAuctionImplementation} from "src/core/proxy/EnglishAuctionImplementation.sol";
import {DutchAuctionImplementation} from "src/core/proxy/DutchAuctionImplementation.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import {AuctionTestHelpers} from "test/utils/auction/AuctionTestHelpers.sol";
import "src/errors/AuctionErrors.sol";

// Import Pausable errors
error EnforcedPause();
error ExpectedPause();

/**
 * @title AuctionFactoryTest
 * @notice Unit tests for AuctionFactory contract
 * @dev Tests factory functionality and unified auction management
 */
contract AuctionFactoryTest is AuctionTestHelpers {
    // ============================================================================
    // EVENTS FOR TESTING
    // ============================================================================

    event AuctionImplementationsDeployed(
        address indexed englishAuctionImplementation,
        address indexed dutchAuctionImplementation,
        address indexed marketplaceWallet
    );

    event AuctionCreatedViaFactory(
        bytes32 indexed auctionId, address indexed auctionContract, address indexed seller, AuctionType auctionType
    );

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        setUpAuctionTests();
    }

    // Allow contract to receive ETH for royalty payments
    receive() external payable override {}
    fallback() external payable {}

    // ============================================================================
    // DEPLOYMENT TESTS
    // ============================================================================

    function test_Constructor_Success() public {
        // Deploy implementations
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();

        // Deploy new factory to test constructor
        vm.expectEmit(true, true, true, true);
        emit AuctionImplementationsDeployed(address(englishImpl), address(dutchImpl), MARKETPLACE_WALLET);

        AuctionFactory newFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));

        // Verify factory state
        assertEq(newFactory.marketplaceWallet(), MARKETPLACE_WALLET);
        assertEq(newFactory.englishAuctionImplementation(), address(englishImpl));
        assertEq(newFactory.dutchAuctionImplementation(), address(dutchImpl));
    }

    function test_Constructor_RevertIfZeroAddress() public {
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();

        vm.expectRevert(Auction__ZeroAddress.selector);
        new AuctionFactory(address(0), address(englishImpl), address(dutchImpl));
    }

    // ============================================================================
    // ENGLISH AUCTION CREATION TESTS
    // ============================================================================

    function test_CreateEnglishAuction_Success() public {
        uint256 tokenId = 1;

        // Approve factory contract
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        // Don't expect exact event since auctionId is calculated

        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), tokenId, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        vm.stopPrank();

        // Verify auction was created and registered
        assertNotEq(auctionId, bytes32(0));

        // Verify proxy contract was created (should not be factory address)
        address proxyAddress = auctionFactory.getAuctionContract(auctionId);
        assertNotEq(proxyAddress, address(0));
        assertNotEq(proxyAddress, address(auctionFactory));

        // Verify auction details
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.nftContract, address(mockERC721));
        assertEq(auction.tokenId, tokenId);
        assertEq(auction.seller, SELLER);
        assertEq(uint256(auction.auctionType), uint256(AuctionType.ENGLISH));
    }

    function test_CreateEnglishAuction_RevertIfPaused() public {
        // Pause factory
        auctionFactory.setPaused(true);

        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        vm.expectRevert(EnforcedPause.selector);
        auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        vm.stopPrank();
    }

    // ============================================================================
    // DUTCH AUCTION CREATION TESTS
    // ============================================================================

    function test_CreateDutchAuction_Success() public {
        uint256 tokenId = 1;

        // Approve factory's Dutch auction contract
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        // Don't check exact auctionId and proxy address since they're dynamically calculated
        vm.expectEmit(false, false, true, true);
        emit AuctionCreatedViaFactory(
            bytes32(0), // Will be calculated - don't check this field
            address(0), // Proxy address will be calculated - don't check this field
            SELLER,
            AuctionType.DUTCH
        );

        bytes32 auctionId = auctionFactory.createDutchAuction(
            address(mockERC721),
            tokenId,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            DEFAULT_PRICE_DROP
        );

        vm.stopPrank();

        // Verify auction was created and registered
        assertNotEq(auctionId, bytes32(0));

        // Verify proxy contract was created (should not be factory address)
        address proxyAddress = auctionFactory.getAuctionContract(auctionId);
        assertNotEq(proxyAddress, address(0));
        assertNotEq(proxyAddress, address(auctionFactory));

        // Verify auction details
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.nftContract, address(mockERC721));
        assertEq(auction.tokenId, tokenId);
        assertEq(auction.seller, SELLER);
        assertEq(uint256(auction.auctionType), uint256(AuctionType.DUTCH));
    }

    // ============================================================================
    // AUCTION INTERACTION TESTS
    // ============================================================================

    function test_PlaceBid_ThroughFactory_Success() public {
        // Create English auction through factory
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Place bid through factory
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        // Verify bid was placed
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.highestBidder, BIDDER1);
        assertEq(auction.highestBid, DEFAULT_START_PRICE);
    }

    function test_BuyNow_ThroughFactory_Success() public {
        // Create Dutch auction through factory
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createDutchAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION, DEFAULT_PRICE_DROP
        );
        vm.stopPrank();

        // Buy through factory
        uint256 currentPrice = auctionFactory.getCurrentPrice(auctionId);

        vm.prank(BIDDER1);
        auctionFactory.buyNow{value: currentPrice}(auctionId);

        // Verify purchase
        assertNFTOwnership(address(mockERC721), 1, BIDDER1);

        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(AuctionStatus.SETTLED));
    }

    function test_CancelAuction_ThroughFactory_Success() public {
        // Create auction through factory
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        // Cancel through factory
        auctionFactory.cancelAuction(auctionId);
        vm.stopPrank();

        // Verify cancellation
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(AuctionStatus.CANCELLED));
    }

    function test_SettleAuction_ThroughFactory_Success() public {
        // Create and run English auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Place bid
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        // Fast forward to end
        fastForwardToAuctionEnd(auctionId);

        // Settle through factory
        auctionFactory.settleAuction(auctionId);

        // Verify settlement
        assertNFTOwnership(address(mockERC721), 1, BIDDER1);

        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(AuctionStatus.SETTLED));
    }

    function test_WithdrawBid_ThroughFactory_Success() public {
        // Create English auction and place multiple bids
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Place two bids
        vm.prank(BIDDER1);
        auctionFactory.placeBid{value: DEFAULT_START_PRICE}(auctionId);

        uint256 secondBid = calculateMinNextBid(DEFAULT_START_PRICE);
        vm.prank(BIDDER2);
        auctionFactory.placeBid{value: secondBid}(auctionId);

        // Withdraw refund through factory
        uint256 balanceBefore = BIDDER1.balance;
        vm.prank(BIDDER1);
        auctionFactory.withdrawBid(auctionId);

        // Verify refund
        assertEq(BIDDER1.balance, balanceBefore + DEFAULT_START_PRICE);
    }

    // ============================================================================
    // VIEW FUNCTION TESTS
    // ============================================================================

    function test_GetAuction_RevertIfNotFound() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.expectRevert(Auction__AuctionNotFound.selector);
        auctionFactory.getAuction(nonExistentId);
    }

    function test_GetCurrentPrice_Success() public {
        // Create Dutch auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createDutchAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION, DEFAULT_PRICE_DROP
        );
        vm.stopPrank();

        uint256 currentPrice = auctionFactory.getCurrentPrice(auctionId);
        assertEq(currentPrice, DEFAULT_START_PRICE);

        // Fast forward and check price drop
        fastForward(1 hours);
        uint256 newPrice = auctionFactory.getCurrentPrice(auctionId);
        assertLt(newPrice, currentPrice);
    }

    function test_IsAuctionActive_Success() public {
        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Should be active
        assertTrue(auctionFactory.isAuctionActive(auctionId));

        // Cancel and check
        vm.prank(SELLER);
        auctionFactory.cancelAuction(auctionId);
        assertFalse(auctionFactory.isAuctionActive(auctionId));
    }

    function test_GetAllAuctions_Success() public {
        // Initially empty
        bytes32[] memory auctions = auctionFactory.getAllAuctions();
        assertEq(auctions.length, 0);

        // Create some auctions
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        bytes32 auctionId1 = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        bytes32 auctionId2 = auctionFactory.createDutchAuction(
            address(mockERC721), 2, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION, DEFAULT_PRICE_DROP
        );
        vm.stopPrank();

        // Check all auctions
        auctions = auctionFactory.getAllAuctions();
        assertEq(auctions.length, 2);
        assertEq(auctions[0], auctionId1);
        assertEq(auctions[1], auctionId2);
    }

    function test_GetUserAuctions_Success() public {
        // Initially empty
        bytes32[] memory userAuctions = auctionFactory.getUserAuctions(SELLER);
        assertEq(userAuctions.length, 0);

        // Create auction
        vm.startPrank(SELLER);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), 1, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );
        vm.stopPrank();

        // Check user auctions
        userAuctions = auctionFactory.getUserAuctions(SELLER);
        assertEq(userAuctions.length, 1);
        assertEq(userAuctions[0], auctionId);

        // Other user should have no auctions
        bytes32[] memory otherUserAuctions = auctionFactory.getUserAuctions(BIDDER1);
        assertEq(otherUserAuctions.length, 0);
    }

    // ============================================================================
    // ADMIN FUNCTION TESTS
    // ============================================================================

    function test_SetPaused_Success() public {
        // Initially not paused
        assertFalse(auctionFactory.paused());

        // Pause
        auctionFactory.setPaused(true);
        assertTrue(auctionFactory.paused());

        // Unpause
        auctionFactory.setPaused(false);
        assertFalse(auctionFactory.paused());
    }

    function test_SetPaused_RevertIfNotOwner() public {
        vm.prank(BIDDER1);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), BIDDER1));
        auctionFactory.setPaused(true);
    }

    function test_SetMarketplaceWallet_Success() public {
        address newWallet = address(0x999);

        auctionFactory.setMarketplaceWallet(newWallet);
        assertEq(auctionFactory.marketplaceWallet(), newWallet);
    }

    function test_SetMarketplaceWallet_RevertIfZeroAddress() public {
        vm.expectRevert(Auction__ZeroAddress.selector);
        auctionFactory.setMarketplaceWallet(address(0));
    }

    function test_SetMarketplaceWallet_RevertIfNotOwner() public {
        vm.prank(BIDDER1);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), BIDDER1));
        auctionFactory.setMarketplaceWallet(address(0x999));
    }
}
