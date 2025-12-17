// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {EnglishAuction} from "src/core/auction/EnglishAuction.sol";
import {DutchAuction} from "src/core/auction/DutchAuction.sol";
import {EnglishAuctionImplementation} from "src/core/proxy/EnglishAuctionImplementation.sol";
import {DutchAuctionImplementation} from "src/core/proxy/DutchAuctionImplementation.sol";
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import {MarketplaceValidator} from "src/core/validation/MarketplaceValidator.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
/**
 * @title AuctionTestHelpers
 * @notice Helper contract for auction testing
 * @dev Provides common test utilities and setup functions
 */

contract AuctionTestHelpers is Test {
    // ============================================================================
    // TEST CONSTANTS
    // ============================================================================

    uint256 public constant DEFAULT_START_PRICE = 1 ether;
    uint256 public constant DEFAULT_RESERVE_PRICE = 0.5 ether;
    uint256 public constant DEFAULT_DURATION = 7 days;
    uint256 public constant DEFAULT_PRICE_DROP = 1000; // 10% per hour
    uint256 public constant MIN_BID_INCREMENT = 500; // 5%

    // ============================================================================
    // TEST ADDRESSES
    // ============================================================================

    address public constant MARKETPLACE_WALLET = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BIDDER1 = address(0x3);
    address public constant BIDDER2 = address(0x4);
    address public constant BIDDER3 = address(0x5);

    // ============================================================================
    // CONTRACT INSTANCES
    // ============================================================================

    EnglishAuction public englishAuction;
    DutchAuction public dutchAuction;
    AuctionFactory public auctionFactory;
    MarketplaceValidator public marketplaceValidator;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;

    // ============================================================================
    // SETUP FUNCTIONS
    // ============================================================================

    /**
     * @notice Sets up the basic test environment
     */
    function setUpAuctionTests() public {
        // Deploy mock NFT contracts
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test ERC1155", "TERC1155");

        // Deploy MarketplaceValidator first
        marketplaceValidator = new MarketplaceValidator();

        // Deploy auction contracts
        englishAuction = new EnglishAuction(MARKETPLACE_WALLET);
        dutchAuction = new DutchAuction(MARKETPLACE_WALLET);

        // Deploy implementations for factory
        EnglishAuctionImplementation englishImpl = new EnglishAuctionImplementation();
        DutchAuctionImplementation dutchImpl = new DutchAuctionImplementation();
        auctionFactory = new AuctionFactory(MARKETPLACE_WALLET, address(englishImpl), address(dutchImpl));

        // Set up MarketplaceValidator integration
        _setupMarketplaceValidator();

        // Setup initial balances
        vm.deal(SELLER, 100 ether);
        vm.deal(BIDDER1, 100 ether);
        vm.deal(BIDDER2, 100 ether);
        vm.deal(BIDDER3, 100 ether);
        vm.deal(MARKETPLACE_WALLET, 0);

        // Mint test NFTs
        _mintTestNFTs();
    }

    /**
     * @notice Sets up MarketplaceValidator integration
     */
    function _setupMarketplaceValidator() internal {
        // Register auction factory with validator
        // Since we're using factory pattern, we only need to register the factory once
        marketplaceValidator.registerAuction(address(auctionFactory), 0); // Factory for all auction types

        // Set validator in auction contracts through the factory
        auctionFactory.setMarketplaceValidator(address(marketplaceValidator));
    }

    /**
     * @notice Mints test NFTs for testing
     */
    function _mintTestNFTs() internal {
        // Mint ERC721 tokens to seller
        vm.startPrank(SELLER);
        for (uint256 i = 1; i <= 10; i++) {
            mockERC721.mint(SELLER, i);
        }

        // Mint ERC1155 tokens to seller
        for (uint256 i = 1; i <= 10; i++) {
            mockERC1155.mint(SELLER, i, 100);
        }
        vm.stopPrank();
    }

    // ============================================================================
    // RECEIVE FUNCTION FOR PAYMENT DISTRIBUTION
    // ============================================================================

    /**
     * @notice Allows test contract to receive ETH payments
     * @dev Required for auction payment distribution to work in tests
     */
    receive() external payable virtual {
        // Accept ETH payments silently for testing
    }

    // ============================================================================
    // AUCTION CREATION HELPERS
    // ============================================================================

    /**
     * @notice Creates a basic English auction using the factory
     * @param tokenId Token ID to auction
     * @return auctionId The created auction ID
     */
    function createBasicEnglishAuction(uint256 tokenId) public returns (bytes32 auctionId) {
        vm.startPrank(SELLER);

        // Approve factory contract
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721), tokenId, 1, DEFAULT_START_PRICE, DEFAULT_RESERVE_PRICE, DEFAULT_DURATION
        );

        vm.stopPrank();
        return auctionId;
    }

    /**
     * @notice Creates a custom English auction using factory
     */
    function createEnglishAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration
    ) public returns (bytes32 auctionId) {
        vm.startPrank(SELLER);

        // Approve factory contract
        if (nftContract == address(mockERC721)) {
            mockERC721.setApprovalForAll(address(auctionFactory), true);
        } else {
            mockERC1155.setApprovalForAll(address(auctionFactory), true);
        }

        auctionId =
            auctionFactory.createEnglishAuction(nftContract, tokenId, amount, startPrice, reservePrice, duration);

        vm.stopPrank();
        return auctionId;
    }

    /**
     * @notice Creates a basic Dutch auction using the factory
     * @param tokenId Token ID to auction
     * @return auctionId The created auction ID
     */
    function createBasicDutchAuction(uint256 tokenId) public returns (bytes32 auctionId) {
        vm.startPrank(SELLER);

        // Approve factory's Dutch auction contract
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        auctionId = auctionFactory.createDutchAuction(
            address(mockERC721),
            tokenId,
            1,
            DEFAULT_START_PRICE,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_DURATION,
            DEFAULT_PRICE_DROP
        );

        vm.stopPrank();
        return auctionId;
    }

    /**
     * @notice Creates a custom Dutch auction using factory
     */
    function createDutchAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 priceDropPerHour
    ) public returns (bytes32 auctionId) {
        vm.startPrank(SELLER);

        // Approve factory contract
        if (nftContract == address(mockERC721)) {
            mockERC721.setApprovalForAll(address(auctionFactory), true);
        } else {
            mockERC1155.setApprovalForAll(address(auctionFactory), true);
        }

        auctionId = auctionFactory.createDutchAuction(
            nftContract, tokenId, amount, startPrice, reservePrice, duration, priceDropPerHour
        );

        vm.stopPrank();
        return auctionId;
    }

    // ============================================================================
    // BIDDING HELPERS
    // ============================================================================

    /**
     * @notice Places a bid from a specific bidder using factory
     * @param auctionId The auction ID
     * @param bidder The bidder address
     * @param bidAmount The bid amount
     */
    function placeBidAs(bytes32 auctionId, address bidder, uint256 bidAmount) public {
        vm.prank(bidder);
        auctionFactory.placeBid{value: bidAmount}(auctionId);
    }

    /**
     * @notice Purchases in Dutch auction as specific buyer using factory
     * @param auctionId The auction ID
     * @param buyer The buyer address
     * @param paymentAmount The payment amount
     */
    function buyNowAs(bytes32 auctionId, address buyer, uint256 paymentAmount) public {
        vm.prank(buyer);
        auctionFactory.buyNow{value: paymentAmount}(auctionId);
    }

    // ============================================================================
    // TIME MANIPULATION HELPERS
    // ============================================================================

    /**
     * @notice Fast forwards time by specified duration
     * @param duration Duration to fast forward
     */
    function fastForward(uint256 duration) public {
        vm.warp(block.timestamp + duration);
    }

    /**
     * @notice Fast forwards to auction end
     * @param auctionId The auction ID
     */
    function fastForwardToAuctionEnd(bytes32 auctionId) public {
        // Use factory to get auction details
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        vm.warp(auction.endTime + 1);
    }

    // ============================================================================
    // ASSERTION HELPERS
    // ============================================================================

    /**
     * @notice Asserts auction status using factory
     * @param auctionId The auction ID
     * @param expectedStatus Expected auction status
     */
    function assertAuctionStatus(bytes32 auctionId, AuctionStatus expectedStatus) public {
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(uint256(auction.status), uint256(expectedStatus));
    }

    /**
     * @notice Asserts highest bidder using factory
     * @param auctionId The auction ID
     * @param expectedBidder Expected highest bidder
     */
    function assertHighestBidder(bytes32 auctionId, address expectedBidder) public {
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.highestBidder, expectedBidder);
    }

    /**
     * @notice Asserts highest bid amount using factory
     * @param auctionId The auction ID
     * @param expectedAmount Expected highest bid amount
     */
    function assertHighestBid(bytes32 auctionId, uint256 expectedAmount) public {
        IAuction.Auction memory auction = auctionFactory.getAuction(auctionId);
        assertEq(auction.highestBid, expectedAmount);
    }

    /**
     * @notice Asserts NFT ownership
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param expectedOwner Expected owner
     */
    function assertNFTOwnership(address nftContract, uint256 tokenId, address expectedOwner) public {
        if (nftContract == address(mockERC721)) {
            assertEq(mockERC721.ownerOf(tokenId), expectedOwner);
        } else {
            assertGt(mockERC1155.balanceOf(expectedOwner, tokenId), 0);
        }
    }

    /**
     * @notice Asserts ETH balance
     * @param account Account to check
     * @param expectedBalance Expected balance
     */
    function assertETHBalance(address account, uint256 expectedBalance) public {
        assertEq(account.balance, expectedBalance);
    }

    // ============================================================================
    // CALCULATION HELPERS
    // ============================================================================

    /**
     * @notice Calculates minimum next bid
     * @param currentBid Current highest bid
     * @return minNextBid Minimum next bid amount
     */
    function calculateMinNextBid(uint256 currentBid) public pure returns (uint256 minNextBid) {
        return currentBid + ((currentBid * MIN_BID_INCREMENT) / 10000);
    }

    /**
     * @notice Calculates Dutch auction price at specific time
     * @param startPrice Starting price
     * @param priceDropPerHour Price drop per hour (in basis points)
     * @param hoursElapsed Hours elapsed since start
     * @param reservePrice Reserve price
     * @return currentPrice Current calculated price
     */
    function calculateDutchPrice(
        uint256 startPrice,
        uint256 priceDropPerHour,
        uint256 hoursElapsed,
        uint256 reservePrice
    ) public pure returns (uint256 currentPrice) {
        uint256 totalDrop = (startPrice * priceDropPerHour * hoursElapsed) / 10000;

        if (totalDrop >= startPrice) {
            return reservePrice;
        }

        uint256 calculatedPrice = startPrice - totalDrop;
        return calculatedPrice < reservePrice ? reservePrice : calculatedPrice;
    }
}
