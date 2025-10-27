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

// Interfaces
import {IAuction} from "src/interfaces/IAuction.sol";

// Mock contracts
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title AdvancedMarketplaceScenarios
 * @notice Advanced integration tests for complex marketplace scenarios
 */
contract AdvancedMarketplaceScenariosTest is Test {
    // Core contracts
    MarketplaceValidator public validator;
    ERC721NFTExchange public erc721Exchange;
    ERC1155NFTExchange public erc1155Exchange;
    AuctionFactory public auctionFactory;
    OfferManager public offerManager;
    BundleManager public bundleManager;
    MarketplaceAccessControl public accessControl;
    AdvancedFeeManager public feeManager;

    // Mock contracts
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC20 public mockERC20;

    // Test addresses
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    address public user4 = address(0x5);
    address public marketplaceWallet = address(0x6);

    // Test constants
    uint256 public constant PRICE_1_ETH = 1 ether;
    uint256 public constant DURATION_1_DAY = 86400;
    uint256 public constant DURATION_7_DAYS = 604800;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy core contracts
        validator = new MarketplaceValidator();
        accessControl = new MarketplaceAccessControl();
        feeManager = new AdvancedFeeManager(address(accessControl), marketplaceWallet);

        // Deploy exchanges directly
        erc721Exchange = new ERC721NFTExchange();
        erc721Exchange.initialize(marketplaceWallet, owner);

        erc1155Exchange = new ERC1155NFTExchange();
        erc1155Exchange.initialize(marketplaceWallet, owner);

        // Deploy auction factory
        auctionFactory = new AuctionFactory(marketplaceWallet);

        // Deploy advanced features
        offerManager = new OfferManager(address(accessControl), address(feeManager));
        bundleManager = new BundleManager(address(accessControl), address(feeManager));

        // Configure contracts
        validator.registerExchange(address(erc721Exchange), 0);
        validator.registerExchange(address(erc1155Exchange), 1);
        validator.registerAuction(address(auctionFactory.englishAuction()), 0);
        validator.registerAuction(address(auctionFactory.dutchAuction()), 1);
        auctionFactory.setMarketplaceValidator(address(validator));

        // Deploy mock contracts
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test Multi", "TMULTI");
        mockERC20 = new MockERC20("Test Token", "TTOKEN", 18);

        // Setup test data
        for (uint256 i = 1; i <= 10; i++) {
            mockERC721.mint(user1, i);
            mockERC1155.mint(user1, i, 100);
        }

        mockERC20.mint(user1, 1000 ether);
        mockERC20.mint(user2, 1000 ether);
        mockERC20.mint(user3, 1000 ether);

        // Give users ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);

        vm.stopPrank();

        // Setup approvals
        vm.startPrank(user1);
        mockERC721.setApprovalForAll(address(erc721Exchange), true);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        mockERC721.setApprovalForAll(address(bundleManager), true);
        mockERC1155.setApprovalForAll(address(erc1155Exchange), true);
        mockERC1155.setApprovalForAll(address(bundleManager), true);
        mockERC20.approve(address(offerManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        mockERC20.approve(address(offerManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        mockERC20.approve(address(offerManager), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice Test concurrent auctions and listings
     */
    function test_ConcurrentAuctionsAndListings() public {
        console2.log("\n=== Test: Concurrent Auctions and Listings ===");

        vm.startPrank(user1);

        // Create multiple listings directly on ERC721 exchange
        for (uint256 i = 1; i <= 3; i++) {
            erc721Exchange.listNFT(
                address(mockERC721),
                i,
                PRICE_1_ETH * i,
                DURATION_7_DAYS
            );
        }
        console2.log("Created 3 concurrent listings");

        // Create multiple auctions
        for (uint256 i = 4; i <= 6; i++) {
            auctionFactory.createEnglishAuction(
                address(mockERC721), i, 1, PRICE_1_ETH * i, (PRICE_1_ETH * i) / 2, DURATION_1_DAY
            );
        }
        console2.log("Created 3 concurrent auctions");

        vm.stopPrank();

        console2.log("All concurrent operations successful");
    }

    /**
     * @notice Test high-volume trading scenario
     */
    function test_HighVolumeTrading() public {
        console2.log("\n=== Test: High Volume Trading ===");

        // Create 10 listings
        vm.startPrank(user1);
        bytes32[] memory listingIds = new bytes32[](10);

        for (uint256 i = 1; i <= 10; i++) {
            listingIds[i - 1] = erc721Exchange.getGeneratedListingId(address(mockERC721), i, user1);
            erc721Exchange.listNFT(address(mockERC721), i, PRICE_1_ETH, DURATION_7_DAYS);
        }
        vm.stopPrank();

        // Buy all listings rapidly
        vm.startPrank(user2);

        for (uint256 i = 0; i < 10; i++) {
            uint256 totalPrice = erc721Exchange.getBuyerSeesPrice(listingIds[i]);
            erc721Exchange.buyNFT{value: totalPrice}(listingIds[i]);
        }
        vm.stopPrank();

        // Verify all transfers
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(mockERC721.ownerOf(i), user2);
        }
        console2.log("High volume trading completed successfully");
    }

    /**
     * @notice Test complex bundle scenarios
     */
    function test_ComplexBundleScenarios() public {
        console2.log("\n=== Test: Complex Bundle Scenarios ===");

        vm.startPrank(user1);

        // Create large bundle with mixed NFT types
        BundleManager.BundleItem[] memory items = new BundleManager.BundleItem[](5);

        // Add ERC721 items
        for (uint256 i = 0; i < 3; i++) {
            items[i] = BundleManager.BundleItem({
                collection: address(mockERC721),
                tokenId: i + 1,
                amount: 1,
                tokenType: BundleManager.TokenType.ERC721,
                isIncluded: true
            });
        }

        // Add ERC1155 items
        for (uint256 i = 3; i < 5; i++) {
            items[i] = BundleManager.BundleItem({
                collection: address(mockERC1155),
                tokenId: i - 2,
                amount: 10,
                tokenType: BundleManager.TokenType.ERC1155,
                isIncluded: true
            });
        }

        bytes32 bundleId = bundleManager.createBundle(
            items,
            5 ether, // total price
            2000, // 20% discount
            address(0), // ETH payment
            block.timestamp + DURATION_7_DAYS,
            "Complex Bundle Test",
            ""
        );

        vm.stopPrank();

        // Purchase bundle
        vm.startPrank(user2);
        uint256 bundlePrice = bundleManager.getBundlePrice(bundleId);
        bundleManager.purchaseBundle{value: bundlePrice}(bundleId);
        vm.stopPrank();

        // Verify all items transferred
        for (uint256 i = 1; i <= 3; i++) {
            assertEq(mockERC721.ownerOf(i), user2);
        }
        for (uint256 i = 1; i <= 2; i++) {
            assertEq(mockERC1155.balanceOf(user2, i), 10);
        }

        console2.log("Complex bundle scenario completed");
    }

    /**
     * @notice Test offer system edge cases
     */
    function test_OfferSystemEdgeCases() public {
        console2.log("\n=== Test: Offer System Edge Cases ===");

        // Create multiple offers for same NFT
        vm.startPrank(user2);
        bytes32 offer1 = offerManager.createNFTOffer{value: 0.5 ether}(
            address(mockERC721), 1, address(0), 0.5 ether, block.timestamp + DURATION_7_DAYS
        );
        vm.stopPrank();

        vm.startPrank(user3);
        bytes32 offer2 = offerManager.createNFTOffer{value: 0.8 ether}(
            address(mockERC721), 1, address(0), 0.8 ether, block.timestamp + DURATION_7_DAYS
        );
        vm.stopPrank();

        vm.startPrank(user4);
        bytes32 offer3 = offerManager.createNFTOffer{value: 1.2 ether}(
            address(mockERC721), 1, address(0), 1.2 ether, block.timestamp + DURATION_7_DAYS
        );
        vm.stopPrank();

        // Accept highest offer
        vm.startPrank(user1);
        mockERC721.setApprovalForAll(address(offerManager), true);
        offerManager.acceptNFTOffer(offer3);
        vm.stopPrank();

        // Verify transfer
        assertEq(mockERC721.ownerOf(1), user4);
        console2.log("Multiple offers scenario completed");
    }
}
