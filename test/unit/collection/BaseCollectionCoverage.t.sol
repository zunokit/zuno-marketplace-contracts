// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {Collection__InvalidAmount} from "src/errors/CollectionErrors.sol";
import "src/errors/FeeErrors.sol";

/**
 * @title BaseCollectionCoverageTest
 * @notice Additional tests to boost BaseCollection coverage to >90%
 * @dev Focuses on edge cases and branch coverage
 */
contract BaseCollectionCoverageTest is Test {
    CoverageTestableBaseCollection testableCollection;

    address constant CREATOR = address(0x123);
    address constant USER = address(0x456);

    function setUp() public {
        CollectionParams memory params = CollectionParams({
            name: "Test Collection",
            symbol: "TEST",
            owner: CREATOR,
            description: "Test Description",
            mintPrice: 0,
            royaltyFee: 1000, // 10% royalty
            maxSupply: 0,
            mintLimitPerWallet: 0,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0,
            publicMintPrice: 0,
            allowlistStageDuration: 0,
            tokenURI: "https://test.com/"
        });

        vm.prank(CREATOR);
        testableCollection = new CoverageTestableBaseCollection(params);

        vm.deal(USER, 100 ether);
        vm.deal(CREATOR, 100 ether);
    }

    // ============================================================================
    // CONSTRUCTOR EDGE CASES
    // ============================================================================

    function test_Constructor_ZeroRoyalty() public {
        CollectionParams memory params = CollectionParams({
            name: "Zero Royalty",
            symbol: "ZERO",
            owner: CREATOR,
            description: "Zero Royalty Description",
            mintPrice: 0,
            royaltyFee: 0, // 0% royalty
            maxSupply: 0,
            mintLimitPerWallet: 0,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0,
            publicMintPrice: 0,
            allowlistStageDuration: 0,
            tokenURI: "https://zero.com/"
        });

        vm.prank(CREATOR);
        CoverageTestableBaseCollection collection = new CoverageTestableBaseCollection(params);

        assertEq(collection.s_feeContract().getRoyaltyFee(), 0);
    }

    function test_Constructor_MaxRoyalty() public {
        CollectionParams memory params = CollectionParams({
            name: "Max Royalty",
            symbol: "MAX",
            owner: CREATOR,
            description: "Max Royalty Description",
            mintPrice: 0,
            royaltyFee: 1000, // 10% royalty (maximum)
            maxSupply: 0,
            mintLimitPerWallet: 0,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0,
            publicMintPrice: 0,
            allowlistStageDuration: 0,
            tokenURI: "https://max.com/"
        });

        vm.prank(CREATOR);
        CoverageTestableBaseCollection collection = new CoverageTestableBaseCollection(params);

        assertEq(collection.s_feeContract().getRoyaltyFee(), 1000);
    }

    function test_Constructor_RevertExcessiveRoyalty() public {
        CollectionParams memory params = CollectionParams({
            name: "Excessive Royalty",
            symbol: "EXCESS",
            owner: CREATOR,
            description: "Excessive Royalty Description",
            mintPrice: 0,
            royaltyFee: 10001, // Over 100%
            maxSupply: 0,
            mintLimitPerWallet: 0,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0,
            publicMintPrice: 0,
            allowlistStageDuration: 0,
            tokenURI: "https://excess.com/"
        });

        vm.prank(CREATOR);
        vm.expectRevert(Fee__InvalidRoyaltyFee.selector);
        new CoverageTestableBaseCollection(params);
    }

    // ============================================================================
    // GETTER FUNCTION TESTS
    // ============================================================================

    function test_GetDescription() public {
        assertEq(testableCollection.getDescription(), "Test Description");
    }

    function test_GetMintPrice() public {
        assertEq(testableCollection.getMintPrice(), 0);
    }

    function test_GetMaxSupply() public {
        assertEq(testableCollection.getMaxSupply(), 0);
    }

    function test_GetMintLimitPerWallet() public {
        assertEq(testableCollection.getMintLimitPerWallet(), 0);
    }

    function test_GetMintStartTime() public {
        assertEq(testableCollection.getMintStartTime(), block.timestamp);
    }

    function test_GetTotalMinted() public {
        assertEq(testableCollection.getTotalMinted(), 0);
    }

    function test_GetAllowlistMintPrice() public {
        assertEq(testableCollection.getAllowlistMintPrice(), 0);
    }

    function test_GetPublicMintPrice() public {
        assertEq(testableCollection.getPublicMintPrice(), 0);
    }

    function test_GetAllowlistStageEnd() public {
        assertEq(testableCollection.getAllowlistStageEnd(), block.timestamp);
    }

    function test_IsInAllowlist() public {
        assertFalse(testableCollection.isInAllowlist(USER));
    }

    function test_GetMintedPerWallet() public {
        assertEq(testableCollection.getMintedPerWallet(USER), 0);
    }

    function test_GetFeeContract() public {
        assertTrue(address(testableCollection.getFeeContract()) != address(0));
    }

    // ============================================================================
    // ALLOWLIST TESTS
    // ============================================================================

    function test_AddToAllowlist_Success() public {
        address[] memory addresses = new address[](2);
        addresses[0] = USER;
        addresses[1] = address(0x789);

        vm.prank(CREATOR);
        testableCollection.addToAllowlist(addresses);

        assertTrue(testableCollection.isInAllowlist(USER));
        assertTrue(testableCollection.isInAllowlist(address(0x789)));
    }

    function test_AddToAllowlist_RevertNotOwner() public {
        address[] memory addresses = new address[](1);
        addresses[0] = USER;

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), USER));
        testableCollection.addToAllowlist(addresses);
    }

    function test_AddToAllowlist_EmptyArray() public {
        address[] memory addresses = new address[](0);

        vm.prank(CREATOR);
        vm.expectRevert(abi.encodeWithSelector(Collection__InvalidAmount.selector));
        testableCollection.addToAllowlist(addresses);
    }

    // ============================================================================
    // MINT INFO TESTS
    // ============================================================================

    function test_GetMintInfo() public {
        (
            uint256 currentTime,
            uint256 mintStartTime,
            uint256 allowlistStageEnd,,
            uint256 currentMintPrice,
            uint256 allowlistPrice,
            uint256 publicPrice,
            uint256 totalMinted,
            uint256 maxSupply,
            uint256 mintedPerWallet,
            uint256 mintLimitPerWallet,
            bool accountInAllowlist
        ) = testableCollection.getMintInfo(USER);

        assertEq(currentTime, block.timestamp);
        assertEq(mintStartTime, block.timestamp);
        assertEq(allowlistStageEnd, block.timestamp);
        assertEq(currentMintPrice, 0);
        assertEq(allowlistPrice, 0);
        assertEq(publicPrice, 0);
        assertEq(totalMinted, 0);
        assertEq(maxSupply, 0);
        assertEq(mintedPerWallet, 0);
        assertEq(mintLimitPerWallet, 0);
        assertFalse(accountInAllowlist);
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    function test_ZeroAddressInAllowlist() public {
        address[] memory addresses = new address[](1);
        addresses[0] = address(0);

        vm.prank(CREATOR);
        vm.expectRevert(abi.encodeWithSelector(Collection__InvalidAmount.selector));
        testableCollection.addToAllowlist(addresses);
    }

    function test_DuplicateAddressInAllowlist() public {
        address[] memory addresses = new address[](2);
        addresses[0] = USER;
        addresses[1] = USER; // Duplicate

        vm.prank(CREATOR);
        testableCollection.addToAllowlist(addresses);

        assertTrue(testableCollection.isInAllowlist(USER));
    }

    function test_LargeAllowlistArray() public {
        address[] memory addresses = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            addresses[i] = address(uint160(i + 1000));
        }

        vm.prank(CREATOR);
        testableCollection.addToAllowlist(addresses);

        // Check first and last addresses
        assertTrue(testableCollection.isInAllowlist(address(1000)));
        assertTrue(testableCollection.isInAllowlist(address(1099)));
    }
}

/**
 * @title CoverageTestableBaseCollection
 * @notice Test contract that exposes BaseCollection functionality for coverage testing
 */
contract CoverageTestableBaseCollection is BaseCollection {
    constructor(CollectionParams memory params) BaseCollection(params) {}
}
