// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Core contracts
import {MarketplaceValidator} from "src/core/validation/MarketplaceValidator.sol";
import {NFTExchangeFactory} from "src/core/factory/NFTExchangeFactory.sol";
import {NFTExchangeRegistry} from "src/core/exchange/NFTExchangeRegistry.sol";
import {ERC721NFTExchange} from "src/core/exchange/ERC721NFTExchange.sol";
import {ERC1155NFTExchange} from "src/core/exchange/ERC1155NFTExchange.sol";
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {OfferManager} from "src/core/offers/OfferManager.sol";
import {OfferEscrowManager} from "src/core/offers/escrow/OfferEscrowManager.sol";
import {BundleManager} from "src/core/bundles/BundleManager.sol";
import {MarketplaceAccessControl} from "src/core/access/MarketplaceAccessControl.sol";
import {AdvancedFeeManager} from "src/core/fees/AdvancedFeeManager.sol";

// Mock contracts
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title MarketplaceStressTest
 * @notice Stress tests for marketplace performance and gas optimization
 */
contract MarketplaceStressTest is Test {
    // Core contracts
    MarketplaceValidator public validator;
    NFTExchangeFactory public exchangeFactory;
    NFTExchangeRegistry public exchangeRegistry;
    ERC721NFTExchange public erc721Exchange;
    ERC1155NFTExchange public erc1155Exchange;
    AuctionFactory public auctionFactory;
    OfferManager public offerManager;
    OfferEscrowManager public offerEscrowManager;
    BundleManager public bundleManager;
    MarketplaceAccessControl public accessControl;
    AdvancedFeeManager public feeManager;

    // Mock contracts
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC20 public mockERC20;

    // Test addresses
    address public owner = address(0x1);
    address public marketplaceWallet = address(0x2);

    // Dynamic user addresses for stress testing
    address[] public users;
    uint256 public constant NUM_USERS = 50;
    uint256 public constant NUM_NFTS = 100;

    // Gas tracking
    uint256 public totalGasUsed;
    uint256 public maxGasPerOperation;
    uint256 public minGasPerOperation = type(uint256).max;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy all contracts
        _deployContracts();
        _configureContracts();

        // Create test users
        _createTestUsers();

        // Deploy and setup NFTs
        _setupNFTs();

        vm.stopPrank();

        console2.log("Stress test setup completed");
        console2.log("Users created:", NUM_USERS);
        console2.log("NFTs minted:", NUM_NFTS);
    }

    function _deployContracts() internal {
        validator = new MarketplaceValidator();
        accessControl = new MarketplaceAccessControl();
        feeManager = new AdvancedFeeManager(address(accessControl), marketplaceWallet);

        // Deploy exchange factory
        exchangeFactory = new NFTExchangeFactory(marketplaceWallet);

        // Deploy implementation contracts
        address erc721Impl = address(new ERC721NFTExchange());
        address erc1155Impl = address(new ERC1155NFTExchange());

        // Set implementations
        exchangeFactory.setImplementation(NFTExchangeFactory.ExchangeType.ERC721, erc721Impl);
        exchangeFactory.setImplementation(NFTExchangeFactory.ExchangeType.ERC1155, erc1155Impl);

        // Create exchanges
        address erc721Addr = exchangeFactory.createExchange(NFTExchangeFactory.ExchangeType.ERC721);
        address erc1155Addr = exchangeFactory.createExchange(NFTExchangeFactory.ExchangeType.ERC1155);

        erc721Exchange = ERC721NFTExchange(erc721Addr);
        erc1155Exchange = ERC1155NFTExchange(erc1155Addr);

        exchangeRegistry = new NFTExchangeRegistry(address(exchangeFactory));

        auctionFactory = new AuctionFactory(marketplaceWallet);
        offerEscrowManager = new OfferEscrowManager();
        offerManager = new OfferManager(address(accessControl), address(feeManager), address(offerEscrowManager));
        offerEscrowManager.authorizeCaller(address(offerManager));
        bundleManager = new BundleManager(address(accessControl), address(feeManager));
    }

    function _configureContracts() internal {
        validator.registerExchange(address(erc721Exchange), 0);
        validator.registerExchange(address(erc1155Exchange), 1);
        validator.registerAuction(address(auctionFactory.englishAuction()), 0);
        validator.registerAuction(address(auctionFactory.dutchAuction()), 1);
        auctionFactory.setMarketplaceValidator(address(validator));
    }

    function _createTestUsers() internal {
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            vm.deal(user, 1000 ether);
        }
    }

    function _setupNFTs() internal {
        mockERC721 = new MockERC721("Stress Test NFT", "STNFT");
        mockERC1155 = new MockERC1155("Stress Test Multi", "STMULTI");
        mockERC20 = new MockERC20("Stress Test Token", "STT", 18);

        // Mint NFTs to users
        for (uint256 i = 0; i < NUM_NFTS; i++) {
            address user = users[i % NUM_USERS];
            mockERC721.mint(user, i + 1);
            mockERC1155.mint(user, i + 1, 1000);
            mockERC20.mint(user, 10000 ether);
        }

        // Setup approvals for all users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.startPrank(users[i]);
            mockERC721.setApprovalForAll(address(erc721Exchange), true);
            mockERC721.setApprovalForAll(address(exchangeRegistry), true);
            mockERC721.setApprovalForAll(address(auctionFactory), true);
            mockERC1155.setApprovalForAll(address(erc1155Exchange), true);
            mockERC1155.setApprovalForAll(address(exchangeRegistry), true);
            mockERC20.approve(address(offerManager), type(uint256).max);
            vm.stopPrank();
        }
    }

    /**
     * @notice Stress test: Mass listing creation
     */
    function test_MassListingCreation() public {
        console2.log("\n=== Stress Test: Mass Listing Creation ===");

        uint256 startGas = gasleft();
        uint256 numListings = 50;

        for (uint256 i = 0; i < numListings; i++) {
            address user = users[i % NUM_USERS];
            uint256 tokenId = (i % NUM_NFTS) + 1;

            vm.startPrank(user);
            uint256 gasBeforeOp = gasleft();

            erc721Exchange.listNFT(
                address(mockERC721),
                tokenId,
                1 ether + (i * 0.1 ether),
                604800 // 7 days
            );

            uint256 gasUsed = gasBeforeOp - gasleft();
            _trackGasUsage(gasUsed);

            vm.stopPrank();
        }

        uint256 totalGas = startGas - gasleft();
        console2.log("Total listings created:", numListings);
        console2.log("Total gas used:", totalGas);
        console2.log("Average gas per listing:", totalGas / numListings);
        console2.log("Max gas per operation:", maxGasPerOperation);
        console2.log("Min gas per operation:", minGasPerOperation);
    }

    /**
     * @notice Stress test: Rapid trading
     */
    function test_RapidTrading() public {
        console2.log("\n=== Stress Test: Rapid Trading ===");

        // First create listings
        uint256 numTrades = 30;
        bytes32[] memory listingIds = new bytes32[](numTrades);

        for (uint256 i = 0; i < numTrades; i++) {
            address seller = users[i % NUM_USERS];
            uint256 tokenId = (i % NUM_NFTS) + 1;

            vm.startPrank(seller);
            listingIds[i] = erc721Exchange.getGeneratedListingId(address(mockERC721), tokenId, seller);
            erc721Exchange.listNFT(address(mockERC721), tokenId, 1 ether, 604800);
            vm.stopPrank();
        }

        // Now execute rapid purchases
        uint256 startGas = gasleft();

        for (uint256 i = 0; i < numTrades; i++) {
            address buyer = users[(i + 25) % NUM_USERS]; // Different users as buyers

            vm.startPrank(buyer);
            uint256 gasBeforeOp = gasleft();

            uint256 totalPrice = 1 ether + (1 ether * 500) / 10000; // Include fees
            erc721Exchange.buyNFT{value: totalPrice}(listingIds[i]);

            uint256 gasUsed = gasBeforeOp - gasleft();
            _trackGasUsage(gasUsed);

            vm.stopPrank();
        }

        uint256 totalGas = startGas - gasleft();
        console2.log("Total trades executed:", numTrades);
        console2.log("Total gas used:", totalGas);
        console2.log("Average gas per trade:", totalGas / numTrades);
    }

    /**
     * @notice Stress test: Concurrent auctions
     */
    function test_ConcurrentAuctions() public {
        console2.log("\n=== Stress Test: Concurrent Auctions ===");

        uint256 numAuctions = 20;
        bytes32[] memory auctionIds = new bytes32[](numAuctions);

        // Create multiple auctions
        for (uint256 i = 0; i < numAuctions; i++) {
            address seller = users[i % NUM_USERS];
            uint256 tokenId = (i % NUM_NFTS) + 1;

            vm.startPrank(seller);
            uint256 gasBeforeOp = gasleft();

            auctionIds[i] = auctionFactory.createEnglishAuction(
                address(mockERC721),
                tokenId,
                1,
                1 ether + (i * 0.1 ether), // Starting price
                0.5 ether, // Reserve price
                86400 // 1 day
            );

            uint256 gasUsed = gasBeforeOp - gasleft();
            _trackGasUsage(gasUsed);

            vm.stopPrank();
        }

        // Place bids on all auctions
        for (uint256 i = 0; i < numAuctions; i++) {
            for (uint256 j = 0; j < 3; j++) {
                // 3 bids per auction
                address bidder = users[(i + j + 10) % NUM_USERS];
                uint256 bidAmount = (1 ether + (i * 0.1 ether)) + ((j + 1) * 0.1 ether);

                vm.startPrank(bidder);
                auctionFactory.placeBid{value: bidAmount}(auctionIds[i]);
                vm.stopPrank();
            }
        }

        console2.log("Concurrent auctions created:", numAuctions);
        console2.log("Total bids placed:", numAuctions * 3);
    }

    /**
     * @notice Stress test: Offer system load
     */
    function test_OfferSystemLoad() public {
        console2.log("\n=== Stress Test: Offer System Load ===");

        uint256 numOffers = 40;

        for (uint256 i = 0; i < numOffers; i++) {
            address offerer = users[i % NUM_USERS];
            uint256 tokenId = (i % NUM_NFTS) + 1;
            uint256 offerAmount = 0.5 ether + (i * 0.01 ether);

            vm.startPrank(offerer);
            uint256 gasBeforeOp = gasleft();

            offerManager.createNFTOffer{value: offerAmount}(
                address(mockERC721),
                tokenId,
                address(0), // ETH payment
                offerAmount,
                block.timestamp + 604800
            );

            uint256 gasUsed = gasBeforeOp - gasleft();
            _trackGasUsage(gasUsed);

            vm.stopPrank();
        }

        console2.log("Offers created:", numOffers);
        console2.log("Average gas per offer:", totalGasUsed / numOffers);
    }

    /**
     * @notice Performance benchmark summary
     */
    function test_PerformanceBenchmark() public view {
        console2.log("\n=== Performance Benchmark Summary ===");
        console2.log("Total operations tested: Multiple");
        console2.log("Max gas per operation:", maxGasPerOperation);
        console2.log("Min gas per operation:", minGasPerOperation);
        console2.log("Total gas tracked:", totalGasUsed);

        // Gas efficiency thresholds
        uint256 maxAcceptableGas = 500000; // 500k gas per operation

        if (maxGasPerOperation <= maxAcceptableGas) {
            console2.log("Gas efficiency: PASSED");
        } else {
            console2.log("Gas efficiency: NEEDS OPTIMIZATION");
        }
    }

    function _trackGasUsage(uint256 gasUsed) internal {
        totalGasUsed += gasUsed;
        if (gasUsed > maxGasPerOperation) {
            maxGasPerOperation = gasUsed;
        }
        if (gasUsed < minGasPerOperation) {
            minGasPerOperation = gasUsed;
        }
    }
}
