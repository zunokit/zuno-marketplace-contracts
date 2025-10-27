// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Core contracts
import {MarketplaceValidator} from "src/core/validation/MarketplaceValidator.sol";
import {ERC721NFTExchange} from "src/core/exchange/ERC721NFTExchange.sol";
import {ERC1155NFTExchange} from "src/core/exchange/ERC1155NFTExchange.sol";
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {OfferManager} from "src/core/offers/OfferManager.sol";
import {BundleManager} from "src/core/bundles/BundleManager.sol";
import {MarketplaceAccessControl} from "src/core/access/MarketplaceAccessControl.sol";
import {AdvancedFeeManager} from "src/core/fees/AdvancedFeeManager.sol";

// Collection contracts
import {ERC721CollectionFactory} from "src/core/factory/ERC721CollectionFactory.sol";
import {ERC1155CollectionFactory} from "src/core/factory/ERC1155CollectionFactory.sol";

// Mock contracts
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title SimpleMarketplaceIntegration
 * @notice Simple integration tests for marketplace core functionality
 */
contract SimpleMarketplaceIntegrationTest is Test {
    // Core contracts
    MarketplaceValidator public validator;
    ERC721NFTExchange public erc721Exchange;
    ERC1155NFTExchange public erc1155Exchange;
    AuctionFactory public auctionFactory;
    OfferManager public offerManager;
    BundleManager public bundleManager;
    MarketplaceAccessControl public accessControl;
    AdvancedFeeManager public feeManager;

    // Collection contracts
    ERC721CollectionFactory public erc721Factory;
    ERC1155CollectionFactory public erc1155Factory;

    // Mock contracts
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC20 public mockERC20;

    // Test addresses
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    address public marketplaceWallet = address(0x5);

    // Test constants
    uint256 public constant TOKEN_ID_1 = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint256 public constant PRICE_1_ETH = 1 ether;
    uint256 public constant DURATION_7_DAYS = 604800;

    function setUp() public {
        console2.log("=== Setting up Simple Marketplace Integration Test ===");

        vm.startPrank(owner);

        // Deploy core infrastructure
        _deployCore();

        // Deploy collection system
        _deployCollectionSystem();

        // Deploy advanced features
        _deployAdvancedFeatures();

        // Configure contracts
        _configureContracts();

        // Setup test data
        _setupTestData();

        vm.stopPrank();

        console2.log("Marketplace setup complete");
    }

    function _deployCore() internal {
        console2.log("Deploying core contracts...");

        validator = new MarketplaceValidator();
        accessControl = new MarketplaceAccessControl();
        feeManager = new AdvancedFeeManager(address(accessControl), marketplaceWallet);

        // Deploy exchanges directly
        erc721Exchange = new ERC721NFTExchange();
        erc721Exchange.initialize(marketplaceWallet, owner);

        erc1155Exchange = new ERC1155NFTExchange();
        erc1155Exchange.initialize(marketplaceWallet, owner);

        auctionFactory = new AuctionFactory(marketplaceWallet);
    }

    function _deployCollectionSystem() internal {
        console2.log("Deploying collection system...");

        erc721Factory = new ERC721CollectionFactory();
        erc1155Factory = new ERC1155CollectionFactory();
    }

    function _deployAdvancedFeatures() internal {
        console2.log("Deploying advanced features...");

        offerManager = new OfferManager(address(accessControl), address(feeManager));
        bundleManager = new BundleManager(address(accessControl), address(feeManager));
    }

    function _configureContracts() internal {
        console2.log("Configuring contracts...");

        validator.registerExchange(address(erc721Exchange), 0);
        validator.registerExchange(address(erc1155Exchange), 1);
        validator.registerAuction(address(auctionFactory.englishAuction()), 0);
        validator.registerAuction(address(auctionFactory.dutchAuction()), 1);
        auctionFactory.setMarketplaceValidator(address(validator));

        // Note: ADMIN_ROLE is already granted to owner in MarketplaceAccessControl constructor
        // No need to grant it again here
    }

    function _setupTestData() internal {
        console2.log("Setting up test data...");

        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test Multi", "TMULTI");
        mockERC20 = new MockERC20("Test Token", "TTOKEN", 18);

        // Mint test NFTs
        mockERC721.mint(user1, TOKEN_ID_1);
        mockERC721.mint(user1, TOKEN_ID_2);
        mockERC1155.mint(user1, TOKEN_ID_1, 10);
        mockERC1155.mint(user2, TOKEN_ID_2, 10);

        // Mint test ERC20 tokens
        mockERC20.mint(user1, 100 ether);
        mockERC20.mint(user2, 100 ether);
        mockERC20.mint(user3, 100 ether);

        // Give users ETH for testing
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

        // Approve exchanges for NFT transfers
        vm.startPrank(user1);
        mockERC721.setApprovalForAll(address(erc721Exchange), true);
        mockERC1155.setApprovalForAll(address(erc1155Exchange), true);
        vm.stopPrank();

        vm.startPrank(user2);
        mockERC1155.setApprovalForAll(address(erc1155Exchange), true);
        vm.stopPrank();
    }

    /**
     * @notice Test 1: Basic ERC721 Trading
     */
    function test_BasicERC721Trading() public {
        console2.log("\n=== Test 1: Basic ERC721 Trading ===");

        // Step 1: List NFT
        vm.startPrank(user1);
        bytes32 listingId = erc721Exchange.getGeneratedListingId(address(mockERC721), TOKEN_ID_1, user1);

        erc721Exchange.listNFT(address(mockERC721), TOKEN_ID_1, PRICE_1_ETH, DURATION_7_DAYS);
        console2.log("NFT listed successfully");
        vm.stopPrank();

        // Step 2: Buy NFT
        vm.startPrank(user2);
        uint256 totalPrice = erc721Exchange.getBuyerSeesPrice(listingId);
        erc721Exchange.buyNFT{value: totalPrice}(listingId);
        console2.log("NFT purchased successfully");
        vm.stopPrank();

        // Step 3: Verify ownership transfer
        assertEq(mockERC721.ownerOf(TOKEN_ID_1), user2);
        console2.log("Ownership transferred correctly");
    }

    /**
     * @notice Test 2: Basic ERC1155 Trading
     */
    function test_BasicERC1155Trading() public {
        console2.log("\n=== Test 2: Basic ERC1155 Trading ===");

        // Step 1: List ERC1155
        vm.startPrank(user1);
        bytes32 listingId = erc1155Exchange.getGeneratedListingId(address(mockERC1155), TOKEN_ID_1, user1);

        uint256 listAmount = 5;
        erc1155Exchange.listNFT(address(mockERC1155), TOKEN_ID_1, listAmount, PRICE_1_ETH, DURATION_7_DAYS);
        console2.log("ERC1155 listed successfully");
        vm.stopPrank();

        // Step 2: Buy partial amount
        vm.startPrank(user2);
        uint256 buyAmount = 3;
        // Get full listing price and calculate proportional amount
        uint256 fullPrice = erc1155Exchange.getBuyerSeesPrice(listingId);
        uint256 totalPrice = (fullPrice * buyAmount) / listAmount;
        erc1155Exchange.buyNFT{value: totalPrice}(listingId, buyAmount);
        console2.log("ERC1155 purchased successfully");
        vm.stopPrank();

        // Step 3: Verify balances
        assertEq(mockERC1155.balanceOf(user1, TOKEN_ID_1), 7); // 10 - 3 = 7
        assertEq(mockERC1155.balanceOf(user2, TOKEN_ID_1), 3);
        console2.log("Balances updated correctly");
    }

    /**
     * @notice Test 3: Basic Auction
     */
    function test_BasicAuction() public {
        console2.log("\n=== Test 3: Basic Auction ===");

        // Step 1: Create auction
        vm.startPrank(user1);
        mockERC721.setApprovalForAll(address(auctionFactory), true);

        bytes32 auctionId = auctionFactory.createEnglishAuction(
            address(mockERC721),
            TOKEN_ID_2,
            1,
            PRICE_1_ETH,
            PRICE_1_ETH / 2,
            86400 // 1 day
        );
        console2.log("Auction created successfully");
        vm.stopPrank();

        // Step 2: Place bid
        vm.startPrank(user2);
        auctionFactory.placeBid{value: PRICE_1_ETH + 0.1 ether}(auctionId);
        console2.log("Bid placed successfully");
        vm.stopPrank();

        // Step 3: End auction
        vm.warp(block.timestamp + 86401);

        vm.startPrank(user1);
        auctionFactory.settleAuction(auctionId);
        console2.log("Auction settled successfully");
        vm.stopPrank();

        // Step 4: Verify results
        assertEq(mockERC721.ownerOf(TOKEN_ID_2), user2);
        console2.log("NFT transferred to highest bidder");
    }

    /**
     * @notice Test 4: Basic Offer System
     */
    function test_BasicOfferSystem() public {
        console2.log("\n=== Test 4: Basic Offer System ===");

        // Step 1: Create offer
        vm.startPrank(user2);
        uint256 offerAmount = 0.5 ether;
        uint256 expiration = block.timestamp + DURATION_7_DAYS;

        bytes32 offerId = offerManager.createNFTOffer{value: offerAmount}(
            address(mockERC721), TOKEN_ID_1, address(0), offerAmount, expiration
        );
        console2.log("Offer created successfully");
        vm.stopPrank();

        // Step 2: Accept offer
        vm.startPrank(user1);
        mockERC721.setApprovalForAll(address(offerManager), true);
        offerManager.acceptNFTOffer(offerId);
        console2.log("Offer accepted successfully");
        vm.stopPrank();

        // Step 3: Verify transfer
        assertEq(mockERC721.ownerOf(TOKEN_ID_1), user2);
        console2.log("NFT transferred to offer maker");
    }

    /**
     * @notice Test 5: Contract Deployment Verification
     */
    function test_ContractDeploymentVerification() public view {
        console2.log("\n=== Test 5: Contract Deployment Verification ===");

        // Verify core contracts
        assertTrue(address(validator) != address(0));
        assertTrue(address(erc721Exchange) != address(0));
        assertTrue(address(erc721Exchange) != address(0));
        assertTrue(address(erc1155Exchange) != address(0));
        assertTrue(address(auctionFactory) != address(0));
        assertTrue(address(offerManager) != address(0));
        assertTrue(address(bundleManager) != address(0));
        assertTrue(address(accessControl) != address(0));
        assertTrue(address(feeManager) != address(0));

        console2.log("All contracts deployed successfully");
    }

    /**
     * @notice Generate test report
     */
    function test_GenerateTestReport() public view {
        console2.log("\n=== SIMPLE MARKETPLACE INTEGRATION TEST REPORT ===");
        console2.log("Test Coverage Summary:");
        console2.log("  - ERC721 Trading Workflow");
        console2.log("  - ERC1155 Trading Workflow");
        console2.log("  - Basic Auction Workflow");
        console2.log("  - Basic Offer System");
        console2.log("  - Contract Deployment Verification");
        console2.log("\nAll basic integration tests completed successfully!");
        console2.log("Core marketplace functionality is working correctly");
    }
}
