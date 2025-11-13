// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {UserHub} from "src/router/UserHub.sol";
import {ExchangeRegistry} from "src/registry/ExchangeRegistry.sol";
import {CollectionRegistry} from "src/registry/CollectionRegistry.sol";
import {FeeRegistry} from "src/registry/FeeRegistry.sol";
import {AuctionRegistry} from "src/registry/AuctionRegistry.sol";
import {IExchangeRegistry} from "src/interfaces/registry/IExchangeRegistry.sol";
import {IAuctionRegistry} from "src/interfaces/registry/IAuctionRegistry.sol";

/**
 * @title UserHubTest
 * @notice Comprehensive unit tests for UserHub contract
 * @dev Tests all getter functions and view functions
 */
contract UserHubTest is Test {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    UserHub public userHub;
    ExchangeRegistry public exchangeRegistry;
    CollectionRegistry public collectionRegistry;
    FeeRegistry public feeRegistry;
    AuctionRegistry public auctionRegistry;

    address public admin;
    address public bundleManager;
    address public offerManager;
    address public listingValidator;
    address public emergencyManager;
    address public accessControl;
    address public historyTracker;
    address public baseFee;
    address public feeManager;
    address public royaltyManager;

    // Mock exchange/factory addresses
    address public erc721Exchange;
    address public erc1155Exchange;
    address public erc721Factory;
    address public erc1155Factory;
    address public englishAuction;
    address public dutchAuction;
    address public auctionFactory;

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        // Setup test accounts
        admin = makeAddr("admin");
        bundleManager = makeAddr("bundleManager");
        offerManager = makeAddr("offerManager");
        listingValidator = makeAddr("listingValidator");
        emergencyManager = makeAddr("emergencyManager");
        accessControl = makeAddr("accessControl");
        historyTracker = makeAddr("historyTracker");
        baseFee = makeAddr("baseFee");
        feeManager = makeAddr("feeManager");
        royaltyManager = makeAddr("royaltyManager");

        // Mock contract addresses
        erc721Exchange = makeAddr("erc721Exchange");
        erc1155Exchange = makeAddr("erc1155Exchange");
        erc721Factory = makeAddr("erc721Factory");
        erc1155Factory = makeAddr("erc1155Factory");
        englishAuction = makeAddr("englishAuction");
        dutchAuction = makeAddr("dutchAuction");
        auctionFactory = makeAddr("auctionFactory");

        vm.startPrank(admin);

        // Deploy registries
        exchangeRegistry = new ExchangeRegistry(admin);
        collectionRegistry = new CollectionRegistry(admin);
        feeRegistry = new FeeRegistry(admin, baseFee, feeManager, royaltyManager);
        auctionRegistry = new AuctionRegistry(admin);

        // Register contracts
        exchangeRegistry.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);
        exchangeRegistry.registerExchange(IExchangeRegistry.TokenStandard.ERC1155, erc1155Exchange);

        collectionRegistry.registerFactory("ERC721", erc721Factory);
        collectionRegistry.registerFactory("ERC1155", erc1155Factory);

        auctionRegistry.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, englishAuction);
        auctionRegistry.registerAuction(IAuctionRegistry.AuctionType.DUTCH, dutchAuction);
        auctionRegistry.updateAuctionFactory(auctionFactory);

        // Deploy UserHub
        userHub = new UserHub(
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry),
            bundleManager,
            offerManager
        );

        vm.stopPrank();
    }

    // ============================================================================
    // CONSTRUCTOR TESTS
    // ============================================================================

    function test_Constructor_Success() public view {
        assertEq(address(userHub.exchangeRegistry()), address(exchangeRegistry));
        assertEq(address(userHub.collectionRegistry()), address(collectionRegistry));
        assertEq(address(userHub.feeRegistry()), address(feeRegistry));
        assertEq(address(userHub.auctionRegistry()), address(auctionRegistry));
        assertEq(userHub.bundleManager(), bundleManager);
        assertEq(userHub.offerManager(), offerManager);
    }

    function test_Constructor_RevertZeroAddress_ExchangeRegistry() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(0), // Zero address
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry),
            bundleManager,
            offerManager
        );
    }

    function test_Constructor_RevertZeroAddress_CollectionRegistry() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(exchangeRegistry),
            address(0), // Zero address
            address(feeRegistry),
            address(auctionRegistry),
            bundleManager,
            offerManager
        );
    }

    function test_Constructor_RevertZeroAddress_FeeRegistry() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(exchangeRegistry),
            address(collectionRegistry),
            address(0), // Zero address
            address(auctionRegistry),
            bundleManager,
            offerManager
        );
    }

    function test_Constructor_RevertZeroAddress_AuctionRegistry() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(0), // Zero address
            bundleManager,
            offerManager
        );
    }

    function test_Constructor_RevertZeroAddress_BundleManager() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry),
            address(0), // Zero address
            offerManager
        );
    }

    function test_Constructor_RevertZeroAddress_OfferManager() public {
        vm.expectRevert(UserHub.UserHub__ZeroAddress.selector);
        new UserHub(
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry),
            bundleManager,
            address(0) // Zero address
        );
    }

    // ============================================================================
    // GET ALL ADDRESSES TESTS
    // ============================================================================

    function test_GetAllAddresses_Success() public view {
        (
            address _erc721Exchange,
            address _erc1155Exchange,
            address _erc721Factory,
            address _erc1155Factory,
            address _englishAuction,
            address _dutchAuction,
            address _auctionFactory,
            address _feeRegistry,
            address _bundleManager,
            address _offerManager
        ) = userHub.getAllAddresses();

        assertEq(_erc721Exchange, erc721Exchange);
        assertEq(_erc1155Exchange, erc1155Exchange);
        assertEq(_erc721Factory, erc721Factory);
        assertEq(_erc1155Factory, erc1155Factory);
        assertEq(_englishAuction, englishAuction);
        assertEq(_dutchAuction, dutchAuction);
        assertEq(_auctionFactory, auctionFactory);
        assertEq(_feeRegistry, address(feeRegistry));
        assertEq(_bundleManager, bundleManager);
        assertEq(_offerManager, offerManager);
    }

    // ============================================================================
    // GET FEE REGISTRY TESTS
    // ============================================================================

    function test_GetFeeRegistry_Success() public view {
        address result = userHub.getFeeRegistry();
        assertEq(result, address(feeRegistry));
    }

    // ============================================================================
    // GET FACTORY FOR TESTS
    // ============================================================================

    function test_GetFactoryFor_ERC721_Success() public view {
        address result = userHub.getFactoryFor("ERC721");
        assertEq(result, erc721Factory);
    }

    function test_GetFactoryFor_ERC1155_Success() public view {
        address result = userHub.getFactoryFor("ERC1155");
        assertEq(result, erc1155Factory);
    }

    // ============================================================================
    // GET AUCTION FOR TESTS
    // ============================================================================

    function test_GetAuctionFor_English_Success() public view {
        address result = userHub.getAuctionFor(IAuctionRegistry.AuctionType.ENGLISH);
        assertEq(result, englishAuction);
    }

    function test_GetAuctionFor_Dutch_Success() public view {
        address result = userHub.getAuctionFor(IAuctionRegistry.AuctionType.DUTCH);
        assertEq(result, dutchAuction);
    }

    // ============================================================================
    // UPDATE ADDITIONAL CONTRACTS TESTS
    // ============================================================================

    function test_UpdateAdditionalContracts_Success() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        assertEq(userHub.listingValidator(), listingValidator);
        assertEq(userHub.emergencyManager(), emergencyManager);
        assertEq(userHub.accessControl(), accessControl);
        assertEq(userHub.historyTracker(), historyTracker);
    }

    // ============================================================================
    // GET ADDITIONAL ADDRESSES TESTS (NEW)
    // ============================================================================

    function test_GetAdditionalAddresses_Success() public {
        // First update the addresses
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        // Then get them all at once
        (address _listingValidator, address _emergencyManager, address _accessControl, address _historyTracker) =
            userHub.getAdditionalAddresses();

        assertEq(_listingValidator, listingValidator);
        assertEq(_emergencyManager, emergencyManager);
        assertEq(_accessControl, accessControl);
        assertEq(_historyTracker, historyTracker);
    }

    function test_GetAdditionalAddresses_BeforeUpdate_ReturnsZeroAddresses() public view {
        (address _listingValidator, address _emergencyManager, address _accessControl, address _historyTracker) =
            userHub.getAdditionalAddresses();

        assertEq(_listingValidator, address(0));
        assertEq(_emergencyManager, address(0));
        assertEq(_accessControl, address(0));
        assertEq(_historyTracker, address(0));
    }

    // ============================================================================
    // GET LISTING VALIDATOR TESTS (NEW)
    // ============================================================================

    function test_GetListingValidator_Success() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        address result = userHub.getListingValidator();
        assertEq(result, listingValidator);
    }

    function test_GetListingValidator_BeforeUpdate_ReturnsZero() public view {
        address result = userHub.getListingValidator();
        assertEq(result, address(0));
    }

    // ============================================================================
    // GET EMERGENCY MANAGER TESTS (NEW)
    // ============================================================================

    function test_GetEmergencyManager_Success() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        address result = userHub.getEmergencyManager();
        assertEq(result, emergencyManager);
    }

    function test_GetEmergencyManager_BeforeUpdate_ReturnsZero() public view {
        address result = userHub.getEmergencyManager();
        assertEq(result, address(0));
    }

    // ============================================================================
    // GET ACCESS CONTROL TESTS (NEW)
    // ============================================================================

    function test_GetAccessControl_Success() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        address result = userHub.getAccessControl();
        assertEq(result, accessControl);
    }

    function test_GetAccessControl_BeforeUpdate_ReturnsZero() public view {
        address result = userHub.getAccessControl();
        assertEq(result, address(0));
    }

    // ============================================================================
    // GET HISTORY TRACKER TESTS (NEW)
    // ============================================================================

    function test_GetHistoryTracker_Success() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        address result = userHub.getHistoryTracker();
        assertEq(result, historyTracker);
    }

    function test_GetHistoryTracker_BeforeUpdate_ReturnsZero() public view {
        address result = userHub.getHistoryTracker();
        assertEq(result, address(0));
    }

    // ============================================================================
    // GET BUNDLE MANAGER TESTS (NEW)
    // ============================================================================

    function test_GetBundleManager_Success() public view {
        address result = userHub.getBundleManager();
        assertEq(result, bundleManager);
    }

    // ============================================================================
    // GET OFFER MANAGER TESTS (NEW)
    // ============================================================================

    function test_GetOfferManager_Success() public view {
        address result = userHub.getOfferManager();
        assertEq(result, offerManager);
    }

    // ============================================================================
    // GET ALL REGISTRIES TESTS (NEW)
    // ============================================================================

    function test_GetAllRegistries_Success() public view {
        (address exchange, address collection, address fee, address auction) = userHub.getAllRegistries();

        assertEq(exchange, address(exchangeRegistry));
        assertEq(collection, address(collectionRegistry));
        assertEq(fee, address(feeRegistry));
        assertEq(auction, address(auctionRegistry));
    }

    // ============================================================================
    // GET SYSTEM STATUS TESTS
    // ============================================================================

    function test_GetSystemStatus_Success() public view {
        (bool isHealthy, address[] memory activeContracts, uint256 timestamp) = userHub.getSystemStatus();

        assertTrue(isHealthy);
        assertEq(activeContracts.length, 6);
        assertEq(activeContracts[0], address(exchangeRegistry));
        assertEq(activeContracts[1], address(collectionRegistry));
        assertEq(activeContracts[2], address(feeRegistry));
        assertEq(activeContracts[3], address(auctionRegistry));
        assertEq(activeContracts[4], bundleManager);
        assertEq(activeContracts[5], offerManager);
        assertEq(timestamp, block.timestamp);
    }

    // ============================================================================
    // VERIFY COLLECTION TESTS
    // ============================================================================

    function test_VerifyCollection_WithoutAccessControl_ReturnsFalse() public view {
        address someCollection = address(0x123);
        bool result = userHub.verifyCollection(someCollection);
        assertFalse(result);
    }

    function test_VerifyCollection_WithAccessControl_ReturnsTrue() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        address someCollection = address(0x456);
        bool result = userHub.verifyCollection(someCollection);
        assertTrue(result); // Placeholder implementation returns true
    }

    // ============================================================================
    // IS PAUSED TESTS
    // ============================================================================

    function test_IsPaused_WithoutEmergencyManager_ReturnsFalse() public view {
        bool result = userHub.isPaused();
        assertFalse(result);
    }

    function test_IsPaused_WithEmergencyManager_ReturnsFalse() public {
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        bool result = userHub.isPaused();
        assertFalse(result); // Placeholder implementation returns false
    }

    // ============================================================================
    // INTEGRATION TESTS
    // ============================================================================

    function test_FullWorkflow_GetAllAddressesThenGetAdditional() public {
        // Step 1: Get all core addresses
        (
            address _erc721Exchange,
            address _erc1155Exchange,
            address _erc721Factory,
            address _erc1155Factory,
            address _englishAuction,
            address _dutchAuction,
            address _auctionFactory,
            address _feeRegistry,
            address _bundleManager,
            address _offerManager
        ) = userHub.getAllAddresses();

        // Verify core addresses
        assertEq(_erc721Exchange, erc721Exchange);
        assertEq(_offerManager, offerManager);

        // Step 2: Update additional contracts
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        // Step 3: Get additional addresses
        (address _listingValidator, address _emergencyManager, address _accessControl, address _historyTracker) =
            userHub.getAdditionalAddresses();

        // Verify additional addresses
        assertEq(_listingValidator, listingValidator);
        assertEq(_emergencyManager, emergencyManager);
        assertEq(_accessControl, accessControl);
        assertEq(_historyTracker, historyTracker);

        // Step 4: Verify individual getters work
        assertEq(userHub.getListingValidator(), listingValidator);
        assertEq(userHub.getEmergencyManager(), emergencyManager);
        assertEq(userHub.getAccessControl(), accessControl);
        assertEq(userHub.getHistoryTracker(), historyTracker);
        assertEq(userHub.getBundleManager(), bundleManager);
        assertEq(userHub.getOfferManager(), offerManager);
    }

    function test_AllGettersReturnConsistentResults() public {
        // Update additional contracts
        userHub.updateAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        // Get via batch function
        (address batch_lv, address batch_em, address batch_ac, address batch_ht) = userHub.getAdditionalAddresses();

        // Get via individual getters
        address individual_lv = userHub.getListingValidator();
        address individual_em = userHub.getEmergencyManager();
        address individual_ac = userHub.getAccessControl();
        address individual_ht = userHub.getHistoryTracker();

        // Verify consistency
        assertEq(batch_lv, individual_lv);
        assertEq(batch_em, individual_em);
        assertEq(batch_ac, individual_ac);
        assertEq(batch_ht, individual_ht);
    }
}

