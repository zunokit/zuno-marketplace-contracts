// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AdminHub} from "src/router/AdminHub.sol";
import {ExchangeRegistry} from "src/registry/ExchangeRegistry.sol";
import {CollectionRegistry} from "src/registry/CollectionRegistry.sol";
import {FeeRegistry} from "src/registry/FeeRegistry.sol";
import {AuctionRegistry} from "src/registry/AuctionRegistry.sol";
import {IExchangeRegistry} from "src/interfaces/registry/IExchangeRegistry.sol";
import {IAuctionRegistry} from "src/interfaces/registry/IAuctionRegistry.sol";

/**
 * @title AdminHubTest
 * @notice Comprehensive unit tests for AdminHub contract
 * @dev Tests all admin functions, access control, and view functions
 */
contract AdminHubTest is Test {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    AdminHub public adminHub;
    ExchangeRegistry public exchangeRegistry;
    CollectionRegistry public collectionRegistry;
    FeeRegistry public feeRegistry;
    AuctionRegistry public auctionRegistry;

    address public admin;
    address public nonAdmin;
    address public baseFee;
    address public feeManager;
    address public royaltyManager;

    // Mock contract addresses
    address public erc721Exchange;
    address public erc1155Exchange;
    address public erc721Factory;
    address public erc1155Factory;
    address public englishAuction;
    address public dutchAuction;
    address public auctionFactory;
    address public listingValidator;
    address public emergencyManager;
    address public accessControl;
    address public historyTracker;
    address public roleManager;
    address public upgradeManager;
    address public configManager;

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        // Setup test accounts
        admin = makeAddr("admin");
        nonAdmin = makeAddr("nonAdmin");
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
        listingValidator = makeAddr("listingValidator");
        emergencyManager = makeAddr("emergencyManager");
        accessControl = makeAddr("accessControl");
        historyTracker = makeAddr("historyTracker");
        roleManager = makeAddr("roleManager");
        upgradeManager = makeAddr("upgradeManager");
        configManager = makeAddr("configManager");

        vm.startPrank(admin);

        // Deploy registries with admin
        exchangeRegistry = new ExchangeRegistry(admin);
        collectionRegistry = new CollectionRegistry(admin);
        feeRegistry = new FeeRegistry(admin, baseFee, feeManager, royaltyManager);
        auctionRegistry = new AuctionRegistry(admin);

        // Deploy AdminHub
        adminHub = new AdminHub(
            admin,
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry)
        );

        // Grant AdminHub the ADMIN_ROLE in each registry so it can call admin functions
        exchangeRegistry.grantRole(exchangeRegistry.ADMIN_ROLE(), address(adminHub));
        collectionRegistry.grantRole(collectionRegistry.ADMIN_ROLE(), address(adminHub));
        auctionRegistry.grantRole(auctionRegistry.ADMIN_ROLE(), address(adminHub));

        vm.stopPrank();
    }

    // ============================================================================
    // CONSTRUCTOR TESTS
    // ============================================================================

    function test_Constructor_Success() public view {
        assertEq(address(adminHub.exchangeRegistry()), address(exchangeRegistry));
        assertEq(address(adminHub.collectionRegistry()), address(collectionRegistry));
        assertEq(address(adminHub.feeRegistry()), address(feeRegistry));
        assertEq(address(adminHub.auctionRegistry()), address(auctionRegistry));

        // Verify admin has ADMIN_ROLE
        assertTrue(adminHub.hasRole(adminHub.ADMIN_ROLE(), admin));
        assertTrue(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Constructor_RevertZeroAddress_Admin() public {
        vm.expectRevert("Admin cannot be zero");
        new AdminHub(
            address(0), // Zero address
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry)
        );
    }

    function test_Constructor_RevertZeroAddress_ExchangeRegistry() public {
        vm.expectRevert("ExchangeRegistry cannot be zero");
        new AdminHub(
            admin,
            address(0), // Zero address
            address(collectionRegistry),
            address(feeRegistry),
            address(auctionRegistry)
        );
    }

    function test_Constructor_RevertZeroAddress_CollectionRegistry() public {
        vm.expectRevert("CollectionRegistry cannot be zero");
        new AdminHub(
            admin,
            address(exchangeRegistry),
            address(0), // Zero address
            address(feeRegistry),
            address(auctionRegistry)
        );
    }

    function test_Constructor_RevertZeroAddress_FeeRegistry() public {
        vm.expectRevert("FeeRegistry cannot be zero");
        new AdminHub(
            admin,
            address(exchangeRegistry),
            address(collectionRegistry),
            address(0), // Zero address
            address(auctionRegistry)
        );
    }

    function test_Constructor_RevertZeroAddress_AuctionRegistry() public {
        vm.expectRevert("AuctionRegistry cannot be zero");
        new AdminHub(
            admin,
            address(exchangeRegistry),
            address(collectionRegistry),
            address(feeRegistry),
            address(0) // Zero address
        );
    }

    // ============================================================================
    // SET ADDITIONAL CONTRACTS TESTS
    // ============================================================================

    function test_SetAdditionalContracts_Success() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AdminHub.ContractsConfigured(listingValidator, emergencyManager, accessControl, historyTracker);
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        assertEq(adminHub.listingValidator(), listingValidator);
        assertEq(adminHub.emergencyManager(), emergencyManager);
        assertEq(adminHub.accessControl(), accessControl);
        assertEq(adminHub.historyTracker(), historyTracker);
    }

    function test_SetAdditionalContracts_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);
    }

    function test_SetAdditionalContracts_CanUpdateMultipleTimes() public {
        address newListingValidator = makeAddr("newListingValidator");
        address newEmergencyManager = makeAddr("newEmergencyManager");

        // First update
        vm.prank(admin);
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        // Second update
        vm.prank(admin);
        adminHub.setAdditionalContracts(newListingValidator, newEmergencyManager, accessControl, historyTracker);

        assertEq(adminHub.listingValidator(), newListingValidator);
        assertEq(adminHub.emergencyManager(), newEmergencyManager);
    }

    // ============================================================================
    // REGISTER EXCHANGE TESTS
    // ============================================================================

    function test_RegisterExchange_ERC721_Success() public {
        vm.prank(admin);
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);

        address registered = exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC721);
        assertEq(registered, erc721Exchange);
    }

    function test_RegisterExchange_ERC1155_Success() public {
        vm.prank(admin);
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC1155, erc1155Exchange);

        address registered = exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC1155);
        assertEq(registered, erc1155Exchange);
    }

    function test_RegisterExchange_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);
    }

    // ============================================================================
    // REGISTER COLLECTION FACTORY TESTS
    // ============================================================================

    function test_RegisterCollectionFactory_ERC721_Success() public {
        vm.prank(admin);
        adminHub.registerCollectionFactory("ERC721", erc721Factory);

        address registered = collectionRegistry.getFactory("ERC721");
        assertEq(registered, erc721Factory);
    }

    function test_RegisterCollectionFactory_ERC1155_Success() public {
        vm.prank(admin);
        adminHub.registerCollectionFactory("ERC1155", erc1155Factory);

        address registered = collectionRegistry.getFactory("ERC1155");
        assertEq(registered, erc1155Factory);
    }

    function test_RegisterCollectionFactory_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.registerCollectionFactory("ERC721", erc721Factory);
    }

    // ============================================================================
    // REGISTER AUCTION TESTS
    // ============================================================================

    function test_RegisterAuction_English_Success() public {
        vm.prank(admin);
        adminHub.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, englishAuction);

        address registered = auctionRegistry.getAuctionContract(IAuctionRegistry.AuctionType.ENGLISH);
        assertEq(registered, englishAuction);
    }

    function test_RegisterAuction_Dutch_Success() public {
        vm.prank(admin);
        adminHub.registerAuction(IAuctionRegistry.AuctionType.DUTCH, dutchAuction);

        address registered = auctionRegistry.getAuctionContract(IAuctionRegistry.AuctionType.DUTCH);
        assertEq(registered, dutchAuction);
    }

    function test_RegisterAuction_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, englishAuction);
    }

    // ============================================================================
    // UPDATE AUCTION FACTORY TESTS
    // ============================================================================

    function test_UpdateAuctionFactory_Success() public {
        vm.prank(admin);
        adminHub.updateAuctionFactory(auctionFactory);

        address registered = auctionRegistry.getAuctionFactory();
        assertEq(registered, auctionFactory);
    }

    function test_UpdateAuctionFactory_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.updateAuctionFactory(auctionFactory);
    }

    function test_UpdateAuctionFactory_CanUpdateMultipleTimes() public {
        address newFactory = makeAddr("newFactory");

        // First update
        vm.prank(admin);
        adminHub.updateAuctionFactory(auctionFactory);

        // Second update
        vm.prank(admin);
        adminHub.updateAuctionFactory(newFactory);

        assertEq(auctionRegistry.getAuctionFactory(), newFactory);
    }

    // ============================================================================
    // GET ALL REGISTRIES TESTS
    // ============================================================================

    function test_GetAllRegistries_Success() public view {
        (address exchange, address collection, address fee, address auction) = adminHub.getAllRegistries();

        assertEq(exchange, address(exchangeRegistry));
        assertEq(collection, address(collectionRegistry));
        assertEq(fee, address(feeRegistry));
        assertEq(auction, address(auctionRegistry));
    }

    // ============================================================================
    // SET MANAGEMENT CONTRACTS TESTS
    // ============================================================================

    function test_SetManagementContracts_Success() public {
        vm.prank(admin);
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);

        assertEq(adminHub.roleManager(), roleManager);
        assertEq(adminHub.upgradeManager(), upgradeManager);
        assertEq(adminHub.configManager(), configManager);
    }

    function test_SetManagementContracts_RevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);
    }

    function test_SetManagementContracts_CanUpdateMultipleTimes() public {
        address newRoleManager = makeAddr("newRoleManager");

        // First update
        vm.prank(admin);
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);

        // Second update
        vm.prank(admin);
        adminHub.setManagementContracts(newRoleManager, upgradeManager, configManager);

        assertEq(adminHub.roleManager(), newRoleManager);
    }

    // ============================================================================
    // GET MANAGEMENT CONTRACTS TESTS
    // ============================================================================

    function test_GetManagementContracts_Success() public {
        vm.prank(admin);
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);

        (address _roleManager, address _upgradeManager, address _configManager) = adminHub.getManagementContracts();

        assertEq(_roleManager, roleManager);
        assertEq(_upgradeManager, upgradeManager);
        assertEq(_configManager, configManager);
    }

    function test_GetManagementContracts_BeforeSet_ReturnsZero() public view {
        (address _roleManager, address _upgradeManager, address _configManager) = adminHub.getManagementContracts();

        assertEq(_roleManager, address(0));
        assertEq(_upgradeManager, address(0));
        assertEq(_configManager, address(0));
    }

    // ============================================================================
    // EMERGENCY PAUSE TESTS
    // ============================================================================

    function test_EmergencyPause_RevertEmergencyManagerNotSet() public {
        vm.prank(admin);
        vm.expectRevert("Emergency manager not set");
        adminHub.emergencyPause();
    }

    function test_EmergencyPause_RevertNotAdmin() public {
        // Set emergency manager first
        vm.prank(admin);
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        vm.prank(nonAdmin);
        vm.expectRevert();
        adminHub.emergencyPause();
    }

    // ============================================================================
    // ACCESS CONTROL TESTS
    // ============================================================================

    function test_HasRole_AdminRole_Success() public view {
        assertTrue(adminHub.hasRole(adminHub.ADMIN_ROLE(), admin));
        assertFalse(adminHub.hasRole(adminHub.ADMIN_ROLE(), nonAdmin));
    }

    function test_HasRole_DefaultAdminRole_Success() public view {
        assertTrue(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), nonAdmin));
    }

    function test_GrantRole_Success() public view {
        // Verify admin has DEFAULT_ADMIN_ROLE first
        assertTrue(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(adminHub.hasRole(adminHub.ADMIN_ROLE(), admin));
    }

    function test_GrantRole_RevertNotAdmin() public view {
        // NonAdmin does not have DEFAULT_ADMIN_ROLE, so they cannot grant roles
        assertFalse(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), nonAdmin));
    }

    function test_RevokeRole_Success() public view {
        // Verify admin can manage roles
        assertTrue(adminHub.hasRole(adminHub.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(adminHub.hasRole(adminHub.ADMIN_ROLE(), admin));
    }

    // ============================================================================
    // INTEGRATION TESTS
    // ============================================================================

    function test_FullAdminWorkflow_Success() public {
        vm.startPrank(admin);

        // Step 1: Register exchanges
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC1155, erc1155Exchange);

        // Step 2: Register factories
        adminHub.registerCollectionFactory("ERC721", erc721Factory);
        adminHub.registerCollectionFactory("ERC1155", erc1155Factory);

        // Step 3: Register auctions
        adminHub.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, englishAuction);
        adminHub.registerAuction(IAuctionRegistry.AuctionType.DUTCH, dutchAuction);
        adminHub.updateAuctionFactory(auctionFactory);

        // Step 4: Set additional contracts
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        // Step 5: Set management contracts
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);

        vm.stopPrank();

        // Verify all registrations
        assertEq(exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC721), erc721Exchange);
        assertEq(collectionRegistry.getFactory("ERC721"), erc721Factory);
        assertEq(auctionRegistry.getAuctionContract(IAuctionRegistry.AuctionType.ENGLISH), englishAuction);
        assertEq(adminHub.listingValidator(), listingValidator);
        assertEq(adminHub.roleManager(), roleManager);
    }

    function test_MultipleAdmins_CanAllPerformAdminActions() public {
        address admin2 = makeAddr("admin2");

        // Verify admin has proper role
        assertTrue(adminHub.hasRole(adminHub.ADMIN_ROLE(), admin));

        // Grant admin2 access to registries directly
        vm.startPrank(admin);
        exchangeRegistry.grantRole(exchangeRegistry.ADMIN_ROLE(), admin2);
        collectionRegistry.grantRole(collectionRegistry.ADMIN_ROLE(), admin2);
        vm.stopPrank();

        // Admin can register exchanges
        vm.prank(admin);
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);

        // Verify registration worked
        assertEq(exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC721), erc721Exchange);
    }

    function test_NonAdmin_CannotPerformAnyAdminAction() public {
        vm.startPrank(nonAdmin);

        // Try all admin functions - all should revert
        vm.expectRevert();
        adminHub.registerExchange(IExchangeRegistry.TokenStandard.ERC721, erc721Exchange);

        vm.expectRevert();
        adminHub.registerCollectionFactory("ERC721", erc721Factory);

        vm.expectRevert();
        adminHub.registerAuction(IAuctionRegistry.AuctionType.ENGLISH, englishAuction);

        vm.expectRevert();
        adminHub.updateAuctionFactory(auctionFactory);

        vm.expectRevert();
        adminHub.setAdditionalContracts(listingValidator, emergencyManager, accessControl, historyTracker);

        vm.expectRevert();
        adminHub.setManagementContracts(roleManager, upgradeManager, configManager);

        vm.stopPrank();
    }
}

