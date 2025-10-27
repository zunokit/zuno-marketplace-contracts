// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "lib/forge-std/src/Test.sol";

// Core Exchange
import {ERC721NFTExchange} from "src/core/exchange/ERC721NFTExchange.sol";
import {ERC1155NFTExchange} from "src/core/exchange/ERC1155NFTExchange.sol";

// Collection System
import {ERC721Collection} from "src/core/collection/ERC721Collection.sol";
import {ERC1155Collection} from "src/core/collection/ERC1155Collection.sol";
import {ERC721CollectionFactory} from "src/core/factory/ERC721CollectionFactory.sol";
import {ERC1155CollectionFactory} from "src/core/factory/ERC1155CollectionFactory.sol";
import {ERC721CollectionImplementation} from "src/core/proxy/ERC721CollectionImplementation.sol";
import {ERC1155CollectionImplementation} from "src/core/proxy/ERC1155CollectionImplementation.sol";
import {CollectionVerifier} from "src/core/collection/CollectionVerifier.sol";

// Auction System
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {EnglishAuction} from "src/core/auction/EnglishAuction.sol";
import {DutchAuction} from "src/core/auction/DutchAuction.sol";

// Advanced Features
import {OfferManager} from "src/core/offers/OfferManager.sol";
import {BundleManager} from "src/core/bundles/BundleManager.sol";
import {AdvancedListingManager} from "src/core/listing/AdvancedListingManager.sol";

// Management
import {AdvancedFeeManager} from "src/core/fees/AdvancedFeeManager.sol";
import {AdvancedRoyaltyManager} from "src/core/fees/AdvancedRoyaltyManager.sol";
import {MarketplaceAccessControl} from "src/core/access/MarketplaceAccessControl.sol";
import {EmergencyManager} from "src/core/security/EmergencyManager.sol";
import {Fee} from "src/common/Fee.sol";

// Validation
import {MarketplaceValidator} from "src/core/validation/MarketplaceValidator.sol";
import {ListingValidator} from "src/core/validation/ListingValidator.sol";

// Analytics
import {ListingHistoryTracker} from "src/core/analytics/ListingHistoryTracker.sol";

// Types
import {CollectionParams} from "src/types/ListingTypes.sol";

// Hub Architecture
import {UserHub} from "src/router/UserHub.sol";
import {ExchangeRegistry} from "src/registry/ExchangeRegistry.sol";
import {CollectionRegistry} from "src/registry/CollectionRegistry.sol";
import {FeeRegistry} from "src/registry/FeeRegistry.sol";
import {AuctionRegistry} from "src/registry/AuctionRegistry.sol";
import {IExchangeRegistry} from "src/interfaces/registry/IExchangeRegistry.sol";
import {IAuctionRegistry} from "src/interfaces/registry/IAuctionRegistry.sol";

// Mocks
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title E2E_BaseSetup
 * @notice Base setup for all E2E tests with complete marketplace deployment
 * @dev Provides test infrastructure, user personas, and helper functions
 */
abstract contract E2E_BaseSetup is Test {
    // ============================================================================
    // CORE CONTRACTS
    // ============================================================================

    ERC721NFTExchange public erc721Exchange;
    ERC1155NFTExchange public erc1155Exchange;

    ERC721CollectionFactory public erc721Factory;
    ERC1155CollectionFactory public erc1155Factory;
    CollectionVerifier public collectionVerifier;

    AuctionFactory public auctionFactory;
    EnglishAuction public englishAuction;
    DutchAuction public dutchAuction;

    OfferManager public offerManager;
    BundleManager public bundleManager;
    AdvancedListingManager public listingManager;

    AdvancedFeeManager public feeManager;
    AdvancedRoyaltyManager public royaltyManager;
    Fee public baseFeeContract;
    MarketplaceAccessControl public accessControl;
    EmergencyManager public emergencyManager;

    MarketplaceValidator public validator;
    ListingValidator public listingValidator;
    ListingHistoryTracker public historyTracker;

    // Hub Architecture
    UserHub public userHub;
    ExchangeRegistry public hubExchangeRegistry;
    CollectionRegistry public hubCollectionRegistry;
    FeeRegistry public hubFeeRegistry;
    AuctionRegistry public hubAuctionRegistry;

    // Mock contracts
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC20 public mockERC20;

    // ============================================================================
    // TEST USER PERSONAS
    // ============================================================================

    address public admin;
    address public operator;
    address public marketplaceWallet;

    address public alice; // Collection creator, seller
    address public bob; // Buyer, bidder
    address public charlie; // Trader (both buyer/seller)
    address public dave; // Offer maker
    address public eve; // Another trader

    // ============================================================================
    // TEST CONSTANTS
    // ============================================================================

    uint256 public constant INITIAL_BALANCE = 1_000 ether;
    uint256 public constant NFT_PRICE = 1 ether;
    uint256 public constant LISTING_DURATION = 7 days;
    uint256 public constant AUCTION_DURATION = 3 days;
    uint256 public constant OFFER_DURATION = 2 days;

    uint256 public constant TAKER_FEE_BPS = 200; // 2%
    uint256 public constant MAKER_FEE_BPS = 100; // 1%
    uint256 public constant ROYALTY_FEE_BPS = 500; // 5%

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public virtual {
        console2.log("\n=== E2E Test Setup Starting ===");

        // Setup user personas
        _setupUsers();

        // Deploy all contracts
        vm.startPrank(admin);
        _deployAccessControl();
        _deployFeeManagement();
        _deployExchanges();
        _deployCollectionSystem();
        _deployAuctionSystem();
        _deployAdvancedFeatures();
        _deployValidationAndAnalytics();
        _deploySecurity();

        // Configure marketplace wallet for auctions
        // englishAuction.setMarketplaceWallet(marketplaceWallet);
        // dutchAuction.setMarketplaceWallet(marketplaceWallet);

        _configureContracts();
        _deployUserHub();
        vm.stopPrank();

        // Setup test data
        _setupTestData();

        console2.log("=== E2E Test Setup Complete ===\n");
    }

    // ============================================================================
    // DEPLOYMENT FUNCTIONS
    // ============================================================================

    function _setupUsers() internal {
        admin = makeAddr("admin");
        operator = makeAddr("operator");
        marketplaceWallet = makeAddr("marketplaceWallet");

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        eve = makeAddr("eve");

        // Fund users
        vm.deal(admin, INITIAL_BALANCE);
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(dave, INITIAL_BALANCE);
        vm.deal(eve, INITIAL_BALANCE);

        console2.log("Users created and funded");
    }

    function _deployAccessControl() internal {
        accessControl = new MarketplaceAccessControl();
        console2.log("Access control deployed:", address(accessControl));
    }

    function _deployFeeManagement() internal {
        // Deploy base Fee contract
        baseFeeContract = new Fee(admin, ROYALTY_FEE_BPS);

        feeManager = new AdvancedFeeManager(address(accessControl), marketplaceWallet);
        royaltyManager = new AdvancedRoyaltyManager(address(accessControl), address(baseFeeContract));

        console2.log("Fee management deployed");
        console2.log("  BaseFee:", address(baseFeeContract));
        console2.log("  FeeManager:", address(feeManager));
        console2.log("  RoyaltyManager:", address(royaltyManager));
    }

    function _deployExchanges() internal {
        erc721Exchange = new ERC721NFTExchange();
        erc721Exchange.initialize(marketplaceWallet, admin);

        erc1155Exchange = new ERC1155NFTExchange();
        erc1155Exchange.initialize(marketplaceWallet, admin);

        console2.log("Exchanges deployed");
        console2.log("  ERC721Exchange:", address(erc721Exchange));
        console2.log("  ERC1155Exchange:", address(erc1155Exchange));
    }

    function _deployCollectionSystem() internal {
        // Deploy factories (they deploy implementations internally)
        erc721Factory = new ERC721CollectionFactory();
        erc1155Factory = new ERC1155CollectionFactory();

        // Deploy verifier
        collectionVerifier = new CollectionVerifier(
            address(accessControl),
            marketplaceWallet,
            0.01 ether // verification fee
        );

        console2.log("Collection system deployed");
        console2.log("  ERC721Factory:", address(erc721Factory));
        console2.log("  ERC1155Factory:", address(erc1155Factory));
    }

    function _deployAuctionSystem() internal {
        auctionFactory = new AuctionFactory(marketplaceWallet);
        englishAuction = auctionFactory.englishAuction();
        dutchAuction = auctionFactory.dutchAuction();

        console2.log("Auction system deployed");
        console2.log("  AuctionFactory:", address(auctionFactory));
        console2.log("  EnglishAuction:", address(englishAuction));
        console2.log("  DutchAuction:", address(dutchAuction));
    }

    function _deployAdvancedFeatures() internal {
        offerManager = new OfferManager(address(accessControl), address(feeManager));
        bundleManager = new BundleManager(address(accessControl), address(feeManager));

        console2.log("Advanced features deployed");
        console2.log("  OfferManager:", address(offerManager));
        console2.log("  BundleManager:", address(bundleManager));
    }

    function _deployValidationAndAnalytics() internal {
        validator = new MarketplaceValidator();
        listingValidator = new ListingValidator(address(accessControl));
        historyTracker = new ListingHistoryTracker(address(accessControl));

        console2.log("Validation and analytics deployed");
    }

    function _deploySecurity() internal {
        emergencyManager = new EmergencyManager(address(validator));

        console2.log("Security contracts deployed");
        console2.log("  EmergencyManager:", address(emergencyManager));
    }

    function _configureContracts() internal {
        // Configure access control
        accessControl.grantRole(accessControl.OPERATOR_ROLE(), operator);

        // Register contracts in validator
        validator.registerExchange(address(erc721Exchange), 0);
        validator.registerExchange(address(erc1155Exchange), 1);

        console2.log("Contracts configured");
    }

    function _deployUserHub() internal {
        // Deploy registries
        hubExchangeRegistry = new ExchangeRegistry(admin);
        hubCollectionRegistry = new CollectionRegistry(admin);
        hubFeeRegistry = new FeeRegistry(admin, address(baseFeeContract), address(feeManager), address(royaltyManager));
        hubAuctionRegistry = new AuctionRegistry(admin);

        // Deploy hub with real managers from setup
        userHub = new UserHub(
            address(hubExchangeRegistry),
            address(hubCollectionRegistry),
            address(hubFeeRegistry),
            address(hubAuctionRegistry),
            address(bundleManager),
            address(offerManager)
        );

        // Register contracts
        vm.startPrank(admin);
        hubExchangeRegistry.registerExchange(IExchangeRegistry.TokenStandard.ERC721, address(erc721Exchange));
        hubExchangeRegistry.registerExchange(IExchangeRegistry.TokenStandard.ERC1155, address(erc1155Exchange));

        hubCollectionRegistry.registerFactory("ERC721", address(erc721Factory));
        hubCollectionRegistry.registerFactory("ERC1155", address(erc1155Factory));

        hubAuctionRegistry.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, address(englishAuction));
        hubAuctionRegistry.registerAuction(IAuctionRegistry.AuctionType.DUTCH, address(dutchAuction));
        hubAuctionRegistry.updateAuctionFactory(address(auctionFactory));
        vm.stopPrank();

        console2.log("UserHub deployed:", address(userHub));
    }

    function _setupTestData() internal {
        // Deploy mock NFT contracts
        vm.startPrank(alice);
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test Multi", "TMULTI");
        vm.stopPrank();

        // Deploy mock ERC20
        mockERC20 = new MockERC20("Test Token", "TST", 18);

        console2.log("Mock contracts deployed");
        console2.log("  MockERC721:", address(mockERC721));
        console2.log("  MockERC1155:", address(mockERC1155));
    }

    // ============================================================================
    // HELPER FUNCTIONS - COLLECTION CREATION
    // ============================================================================

    function createERC721Collection(address creator, string memory name, string memory symbol)
        internal
        returns (address collection)
    {
        CollectionParams memory params = CollectionParams({
            name: name,
            symbol: symbol,
            owner: creator,
            description: "Test Collection",
            mintPrice: 0.1 ether,
            royaltyFee: ROYALTY_FEE_BPS,
            maxSupply: 10000,
            mintLimitPerWallet: 10,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0.05 ether,
            publicMintPrice: 0.1 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "ipfs://test/"
        });

        vm.prank(creator);
        collection = erc721Factory.createERC721Collection(params);

        console2.log("Created ERC721 collection:", collection);
        return collection;
    }

    function createERC1155Collection(address creator, string memory name, string memory symbol)
        internal
        returns (address collection)
    {
        CollectionParams memory params = CollectionParams({
            name: name,
            symbol: symbol,
            owner: creator,
            description: "Test Multi Collection",
            mintPrice: 0.05 ether,
            royaltyFee: ROYALTY_FEE_BPS,
            maxSupply: 100000,
            mintLimitPerWallet: 50,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0.025 ether,
            publicMintPrice: 0.05 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "ipfs://test/"
        });

        vm.prank(creator);
        collection = erc1155Factory.createERC1155Collection(params);

        console2.log("Created ERC1155 collection:", collection);
        return collection;
    }

    // ============================================================================
    // HELPER FUNCTIONS - NFT OPERATIONS
    // ============================================================================

    function mintERC721(address collection, address to, uint256 /* tokenId */ ) internal {
        vm.prank(to);
        ERC721Collection(collection).mint{value: 0.1 ether}(to);
    }

    function mintERC1155(
        address collection,
        address to,
        uint256,
        /* tokenId */
        uint256 amount
    ) internal {
        vm.prank(to);
        ERC1155Collection(collection).mint{value: 0.05 ether * amount}(to, amount);
    }

    function approveERC721(address collection, address _operator, uint256 tokenId) internal {
        vm.prank(ERC721Collection(collection).ownerOf(tokenId));
        ERC721Collection(collection).approve(_operator, tokenId);
    }

    function setApprovalForAllERC721(address collection, address owner, address _operator) internal {
        vm.prank(owner);
        ERC721Collection(collection).setApprovalForAll(_operator, true);
    }

    function setApprovalForAllERC1155(address collection, address owner, address _operator) internal {
        vm.prank(owner);
        ERC1155Collection(collection).setApprovalForAll(_operator, true);
    }

    // ============================================================================
    // HELPER FUNCTIONS - LISTINGS
    // ============================================================================

    // Track originally listed ERC1155 amounts for proportional pricing in tests
    mapping(bytes32 => uint256) internal _listedAmountById;

    function listERC721(address seller, address collection, uint256 tokenId, uint256 price, uint256 duration)
        internal
        returns (bytes32 listingId)
    {
        vm.prank(seller);
        ERC721Collection(collection).setApprovalForAll(address(erc721Exchange), true);

        vm.prank(seller);
        erc721Exchange.listNFT(collection, tokenId, price, duration);

        listingId = erc721Exchange.getGeneratedListingId(collection, tokenId, seller);
        console2.log("Listed ERC721: collection", collection);
        console2.log("  tokenId:", tokenId);
        return listingId;
    }

    function listERC1155(
        address seller,
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 duration
    ) internal returns (bytes32 listingId) {
        vm.prank(seller);
        ERC1155Collection(collection).setApprovalForAll(address(erc1155Exchange), true);

        vm.prank(seller);
        erc1155Exchange.listNFT(collection, tokenId, amount, price, duration);

        listingId = erc1155Exchange.getGeneratedListingId(collection, tokenId, seller);
        _listedAmountById[listingId] = amount;
        console2.log("Listed ERC1155: collection", collection);
        console2.log("  tokenId:", tokenId, "amount:", amount);
        return listingId;
    }

    // ============================================================================
    // HELPER FUNCTIONS - BUYING
    // ============================================================================

    function buyERC721(address buyer, bytes32 listingId) internal {
        uint256 price = erc721Exchange.getBuyerSeesPrice(listingId);

        vm.prank(buyer);
        erc721Exchange.buyNFT{value: price}(listingId);

        console2.log("Buyer", buyer, "purchased listing for", price);
    }

    function buyERC1155(address buyer, bytes32 listingId, uint256 amount) internal {
        uint256 fullLotPrice = erc1155Exchange.getBuyerSeesPrice(listingId);
        uint256 remainingAmount = _listedAmountById[listingId];
        // Scale payment proportionally to the current remaining amount
        uint256 totalPrice = (fullLotPrice * amount) / remainingAmount;

        vm.prank(buyer);
        erc1155Exchange.buyNFT{value: totalPrice}(listingId, amount);

        // Update our tracked remaining amount to reflect the purchase
        _listedAmountById[listingId] = remainingAmount - amount;

        console2.log("Buyer", buyer);
        console2.log("  amount:", amount, "totalPrice:", totalPrice);
    }

    // ============================================================================
    // HELPER FUNCTIONS - BALANCE TRACKING
    // ============================================================================

    struct BalanceSnapshot {
        uint256 buyer;
        uint256 seller;
        uint256 marketplace;
        uint256 royaltyReceiver;
    }

    function snapshotBalances(address buyer, address seller, address marketplace, address royaltyReceiver)
        internal
        view
        returns (BalanceSnapshot memory)
    {
        return BalanceSnapshot({
            buyer: buyer.balance,
            seller: seller.balance,
            marketplace: marketplace.balance,
            royaltyReceiver: royaltyReceiver.balance
        });
    }

    function assertBalanceChanges(
        BalanceSnapshot memory before,
        BalanceSnapshot memory afterSnapshot,
        uint256 expectedBuyerDecrease,
        uint256 expectedSellerIncrease,
        uint256 expectedMarketplaceFee,
        uint256 expectedRoyalty
    ) internal {
        assertApproxEqAbs(before.buyer - afterSnapshot.buyer, expectedBuyerDecrease, 1e15);
        assertApproxEqAbs(
            afterSnapshot.seller - before.seller, expectedSellerIncrease, 1e15, "Seller balance incorrect"
        );
        assertApproxEqAbs(
            afterSnapshot.marketplace - before.marketplace, expectedMarketplaceFee, 1e15, "Marketplace fee incorrect"
        );
        if (expectedRoyalty > 0) {
            assertApproxEqAbs(
                afterSnapshot.royaltyReceiver - before.royaltyReceiver, expectedRoyalty, 1e15, "Royalty incorrect"
            );
        }
    }

    // ============================================================================
    // HELPER FUNCTIONS - ASSERTIONS
    // ============================================================================

    function assertNFTOwner(address collection, uint256 tokenId, address expectedOwner) internal {
        address actualOwner = ERC721Collection(collection).ownerOf(tokenId);
        assertEq(actualOwner, expectedOwner);
    }

    function assertERC1155Balance(address collection, address owner, uint256 tokenId, uint256 expectedBalance)
        internal
    {
        uint256 actualBalance = ERC1155Collection(collection).balanceOf(owner, tokenId);
        assertEq(actualBalance, expectedBalance);
    }

    // ============================================================================
    // HELPER FUNCTIONS - GAS TRACKING
    // ============================================================================

    function logGasUsage(string memory operation, uint256 gasUsed) internal view {
        console2.log(string.concat(operation), gasUsed);
    }

    // ============================================================================
    // HELPER FUNCTIONS - EVENTS
    // ============================================================================

    function expectListingCreated() internal {
        vm.expectEmit(true, true, true, false);
    }

    function expectNFTSold() internal {
        vm.expectEmit(true, true, true, false);
    }

    // ============================================================================
    // RECEIVE/FALLBACK
    // ============================================================================

    receive() external payable {}
    fallback() external payable {}
}
