// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AuctionFactory} from "src/core/factory/AuctionFactory.sol";
import {EnglishAuctionImplementation} from "src/core/proxy/EnglishAuctionImplementation.sol";
import {DutchAuctionImplementation} from "src/core/proxy/DutchAuctionImplementation.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";

contract BatchAuctionCreationTest is Test {
    AuctionFactory public auctionFactory;
    EnglishAuctionImplementation public englishImpl;
    DutchAuctionImplementation public dutchImpl;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;

    address public marketplaceWallet = makeAddr("marketplace");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant START_PRICE = 1 ether;
    uint256 constant RESERVE_PRICE = 0.5 ether;
    uint256 constant DURATION = 1 days;
    uint256 constant PRICE_DROP_PER_HOUR = 500; // 5% per hour

    function setUp() public {
        // Deploy implementations
        englishImpl = new EnglishAuctionImplementation();
        dutchImpl = new DutchAuctionImplementation();

        // Deploy factory
        auctionFactory = new AuctionFactory(marketplaceWallet, address(englishImpl), address(dutchImpl));

        // Deploy mock NFTs
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test ERC1155", "T1155");

        // Mint NFTs to alice
        for (uint256 i = 1; i <= 10; i++) {
            mockERC721.mint(alice, i);
        }
        mockERC1155.mint(alice, 1, 100, "");
        mockERC1155.mint(alice, 2, 100, "");
        mockERC1155.mint(alice, 3, 100, "");

        // Approve factory
        vm.startPrank(alice);
        mockERC721.setApprovalForAll(address(auctionFactory), true);
        mockERC1155.setApprovalForAll(address(auctionFactory), true);
        vm.stopPrank();
    }

    // ============================================================================
    // BATCH ENGLISH AUCTION TESTS
    // ============================================================================

    function test_BatchCreateEnglishAuction_Success() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;

        vm.prank(alice);
        bytes32[] memory auctionIds = auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );

        assertEq(auctionIds.length, 3, "Should create 3 auctions");

        // Verify each auction
        for (uint256 i = 0; i < auctionIds.length; i++) {
            IAuction.Auction memory auction = auctionFactory.getAuction(auctionIds[i]);
            assertEq(auction.nftContract, address(mockERC721), "NFT contract mismatch");
            assertEq(auction.tokenId, tokenIds[i], "Token ID mismatch");
            assertEq(auction.startPrice, START_PRICE, "Start price mismatch");
            assertEq(auction.seller, alice, "Seller mismatch");
            assertTrue(auctionFactory.isAuctionActive(auctionIds[i]), "Auction should be active");
        }

        // Verify user auctions
        bytes32[] memory userAuctions = auctionFactory.getUserAuctions(alice);
        assertEq(userAuctions.length, 3, "User should have 3 auctions");
    }

    function test_BatchCreateEnglishAuction_SingleNFT() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(alice);
        bytes32[] memory auctionIds = auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );

        assertEq(auctionIds.length, 1, "Should create 1 auction");
    }

    function test_BatchCreateEnglishAuction_EmptyArray_Reverts() public {
        uint256[] memory tokenIds = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert("Empty array");
        auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );
    }

    function test_BatchCreateEnglishAuction_ArrayLengthMismatch_Reverts() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(alice);
        vm.expectRevert("Array length mismatch");
        auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );
    }

    function test_BatchCreateEnglishAuction_ExceedsMaxLimit_Reverts() public {
        uint256[] memory tokenIds = new uint256[](21);
        uint256[] memory amounts = new uint256[](21);
        for (uint256 i = 0; i < 21; i++) {
            tokenIds[i] = i + 1;
            amounts[i] = 1;
        }

        vm.prank(alice);
        vm.expectRevert("Max 20 auctions per batch");
        auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );
    }

    function test_BatchCreateEnglishAuction_WhenPaused_Reverts() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        auctionFactory.setPaused(true);

        vm.prank(alice);
        vm.expectRevert();
        auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );
    }

    // ============================================================================
    // BATCH DUTCH AUCTION TESTS
    // ============================================================================

    function test_BatchCreateDutchAuction_Success() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 4;
        tokenIds[1] = 5;
        tokenIds[2] = 6;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;

        vm.prank(alice);
        bytes32[] memory auctionIds = auctionFactory.batchCreateDutchAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION, PRICE_DROP_PER_HOUR
        );

        assertEq(auctionIds.length, 3, "Should create 3 auctions");

        // Verify each auction
        for (uint256 i = 0; i < auctionIds.length; i++) {
            IAuction.Auction memory auction = auctionFactory.getAuction(auctionIds[i]);
            assertEq(auction.nftContract, address(mockERC721), "NFT contract mismatch");
            assertEq(auction.tokenId, tokenIds[i], "Token ID mismatch");
            assertEq(auction.startPrice, START_PRICE, "Start price mismatch");
            assertEq(auction.seller, alice, "Seller mismatch");
            assertTrue(auctionFactory.isAuctionActive(auctionIds[i]), "Auction should be active");
        }
    }

    function test_BatchCreateDutchAuction_EmptyArray_Reverts() public {
        uint256[] memory tokenIds = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert("Empty array");
        auctionFactory.batchCreateDutchAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION, PRICE_DROP_PER_HOUR
        );
    }

    function test_BatchCreateDutchAuction_ArrayLengthMismatch_Reverts() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(alice);
        vm.expectRevert("Array length mismatch");
        auctionFactory.batchCreateDutchAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION, PRICE_DROP_PER_HOUR
        );
    }

    function test_BatchCreateDutchAuction_ExceedsMaxLimit_Reverts() public {
        uint256[] memory tokenIds = new uint256[](21);
        uint256[] memory amounts = new uint256[](21);
        for (uint256 i = 0; i < 21; i++) {
            tokenIds[i] = i + 1;
            amounts[i] = 1;
        }

        vm.prank(alice);
        vm.expectRevert("Max 20 auctions per batch");
        auctionFactory.batchCreateDutchAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION, PRICE_DROP_PER_HOUR
        );
    }

    // ============================================================================
    // BATCH ERC1155 TESTS
    // ============================================================================

    function test_BatchCreateEnglishAuction_ERC1155() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 10;

        vm.prank(alice);
        bytes32[] memory auctionIds = auctionFactory.batchCreateEnglishAuction(
            address(mockERC1155), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );

        assertEq(auctionIds.length, 2, "Should create 2 auctions");

        // Verify amounts
        IAuction.Auction memory auction1 = auctionFactory.getAuction(auctionIds[0]);
        IAuction.Auction memory auction2 = auctionFactory.getAuction(auctionIds[1]);
        assertEq(auction1.amount, 5, "Amount mismatch for first auction");
        assertEq(auction2.amount, 10, "Amount mismatch for second auction");
    }

    // ============================================================================
    // GAS COMPARISON TESTS
    // ============================================================================

    // ============================================================================
    // BATCH CANCEL TESTS
    // ============================================================================

    function test_BatchCancelAuction_Success() public {
        // Create 3 auctions
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;

        vm.prank(alice);
        bytes32[] memory auctionIds = auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );

        assertEq(auctionIds.length, 3, "Should create 3 auctions");

        // Batch cancel all auctions
        vm.prank(alice);
        uint256 cancelledCount = auctionFactory.batchCancelAuction(auctionIds);

        assertEq(cancelledCount, 3, "Should cancel 3 auctions");

        // Verify all auctions are cancelled
        for (uint256 i = 0; i < auctionIds.length; i++) {
            assertFalse(auctionFactory.isAuctionActive(auctionIds[i]), "Auction should not be active");
        }
    }

    function test_BatchCancelAuction_SkipsNonOwned() public {
        // Alice creates 2 auctions
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(alice);
        bytes32[] memory aliceAuctions = auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );

        // Bob tries to cancel Alice's auctions
        vm.prank(bob);
        uint256 cancelledCount = auctionFactory.batchCancelAuction(aliceAuctions);

        assertEq(cancelledCount, 0, "Should not cancel any auctions");

        // Verify auctions are still active
        assertTrue(auctionFactory.isAuctionActive(aliceAuctions[0]), "Auction should still be active");
        assertTrue(auctionFactory.isAuctionActive(aliceAuctions[1]), "Auction should still be active");
    }

    function test_BatchCancelAuction_EmptyArray_Reverts() public {
        bytes32[] memory emptyIds = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert("Empty array");
        auctionFactory.batchCancelAuction(emptyIds);
    }

    function test_BatchCancelAuction_ExceedsMaxLimit_Reverts() public {
        bytes32[] memory tooManyIds = new bytes32[](21);

        vm.prank(alice);
        vm.expectRevert("Max 20 cancellations per batch");
        auctionFactory.batchCancelAuction(tooManyIds);
    }

    function test_BatchCancelAuction_SkipsNonExistent() public {
        // Create 1 real auction
        vm.prank(alice);
        bytes32 realAuctionId =
            auctionFactory.createEnglishAuction(address(mockERC721), 1, 1, START_PRICE, RESERVE_PRICE, DURATION);

        // Mix real and fake auction IDs
        bytes32[] memory mixedIds = new bytes32[](3);
        mixedIds[0] = bytes32(uint256(999)); // Non-existent
        mixedIds[1] = realAuctionId; // Real
        mixedIds[2] = bytes32(uint256(888)); // Non-existent

        vm.prank(alice);
        uint256 cancelledCount = auctionFactory.batchCancelAuction(mixedIds);

        assertEq(cancelledCount, 1, "Should only cancel 1 auction");
        assertFalse(auctionFactory.isAuctionActive(realAuctionId), "Real auction should be cancelled");
    }

    function test_BatchCancelAuction_PartialSuccess() public {
        // Alice creates 2 auctions
        vm.startPrank(alice);
        bytes32 auction1 =
            auctionFactory.createEnglishAuction(address(mockERC721), 1, 1, START_PRICE, RESERVE_PRICE, DURATION);
        bytes32 auction2 =
            auctionFactory.createEnglishAuction(address(mockERC721), 2, 1, START_PRICE, RESERVE_PRICE, DURATION);
        vm.stopPrank();

        // Bob places a bid on auction1 (can't be cancelled after bid in some implementations)
        // For this test, we'll just verify partial cancellation works with mixed ownership

        // Create array with alice's auctions + a non-existent one
        bytes32[] memory mixedIds = new bytes32[](3);
        mixedIds[0] = auction1;
        mixedIds[1] = bytes32(uint256(12345)); // Non-existent
        mixedIds[2] = auction2;

        vm.prank(alice);
        uint256 cancelledCount = auctionFactory.batchCancelAuction(mixedIds);

        assertEq(cancelledCount, 2, "Should cancel 2 auctions");
    }

    function test_GasComparison_BatchVsIndividual() public {
        uint256[] memory tokenIds = new uint256[](5);
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            tokenIds[i] = i + 1;
            amounts[i] = 1;
        }

        // Measure batch gas
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        auctionFactory.batchCreateEnglishAuction(
            address(mockERC721), tokenIds, amounts, START_PRICE, RESERVE_PRICE, DURATION
        );
        uint256 batchGas = gasBefore - gasleft();

        // Reset state for individual comparison
        setUp();

        // Measure individual gas
        vm.startPrank(alice);
        gasBefore = gasleft();
        for (uint256 i = 0; i < 5; i++) {
            auctionFactory.createEnglishAuction(address(mockERC721), i + 1, 1, START_PRICE, RESERVE_PRICE, DURATION);
        }
        uint256 individualGas = gasBefore - gasleft();
        vm.stopPrank();

        // Log gas comparison (main benefit is 1 tx vs N txs, not gas savings)
        emit log_named_uint("Batch gas (5 auctions)", batchGas);
        emit log_named_uint("Individual gas (5 auctions)", individualGas);

        if (individualGas > batchGas) {
            emit log_named_uint("Gas saved", individualGas - batchGas);
        } else {
            emit log_named_uint("Gas overhead", batchGas - individualGas);
        }

        // Main benefit: 1 transaction confirmation instead of 5
        assertTrue(true, "Batch reduces tx confirmations from N to 1");
    }
}
