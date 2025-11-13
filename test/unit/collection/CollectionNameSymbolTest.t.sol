// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC721CollectionFactory} from "src/core/factory/ERC721CollectionFactory.sol";
import {ERC1155CollectionFactory} from "src/core/factory/ERC1155CollectionFactory.sol";
import {ERC721Collection} from "src/core/collection/ERC721Collection.sol";
import {ERC1155Collection} from "src/core/collection/ERC1155Collection.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";

contract CollectionNameSymbolTest is Test {
    ERC721CollectionFactory public erc721Factory;
    ERC1155CollectionFactory public erc1155Factory;

    address public alice = address(0xA11ce);

    function setUp() public {
        erc721Factory = new ERC721CollectionFactory();
        erc1155Factory = new ERC1155CollectionFactory();
    }

    function test_ERC721_NameAndSymbolAreStoredCorrectly() public {
        // Create collection params
        CollectionParams memory params = CollectionParams({
            name: "Test ERC721 Collection",
            symbol: "T721",
            owner: alice,
            description: "Testing name and symbol storage",
            mintPrice: 0.01 ether,
            royaltyFee: 500, // 5%
            maxSupply: 100,
            mintLimitPerWallet: 5,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0.008 ether,
            publicMintPrice: 0.01 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "https://test.com/metadata/"
        });

        // Create collection
        address collectionAddress = erc721Factory.createERC721Collection(params);

        // Cast to ERC721Collection and verify name and symbol
        ERC721Collection collection = ERC721Collection(collectionAddress);

        assertEq(collection.name(), "Test ERC721 Collection");
        assertEq(collection.symbol(), "T721");
    }

    function test_ERC1155_NameAndSymbolAreStoredCorrectly() public {
        // Create collection params
        CollectionParams memory params = CollectionParams({
            name: "Test ERC1155 Collection",
            symbol: "T1155",
            owner: alice,
            description: "Testing name and symbol storage for ERC1155",
            mintPrice: 0.01 ether,
            royaltyFee: 500, // 5%
            maxSupply: 100,
            mintLimitPerWallet: 5,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0.008 ether,
            publicMintPrice: 0.01 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "https://test.com/metadata/"
        });

        // Create collection
        address collectionAddress = erc1155Factory.createERC1155Collection(params);

        // Cast to ERC1155Collection and verify name and symbol
        ERC1155Collection collection = ERC1155Collection(collectionAddress);

        assertEq(collection.name(), "Test ERC1155 Collection");
        assertEq(collection.symbol(), "T1155");
    }

    function test_MultipleCollectionsHaveDifferentNamesAndSymbols() public {
        // Create first ERC721 collection
        CollectionParams memory params1 = CollectionParams({
            name: "First Collection",
            symbol: "FC",
            owner: alice,
            description: "First collection",
            mintPrice: 0.01 ether,
            royaltyFee: 500,
            maxSupply: 100,
            mintLimitPerWallet: 5,
            mintStartTime: block.timestamp,
            allowlistMintPrice: 0.008 ether,
            publicMintPrice: 0.01 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "https://test1.com/metadata/"
        });

        // Create second ERC721 collection
        CollectionParams memory params2 = CollectionParams({
            name: "Second Collection",
            symbol: "SC",
            owner: alice,
            description: "Second collection",
            mintPrice: 0.02 ether,
            royaltyFee: 750,
            maxSupply: 200,
            mintLimitPerWallet: 10,
            mintStartTime: block.timestamp + 1 hours,
            allowlistMintPrice: 0.015 ether,
            publicMintPrice: 0.02 ether,
            allowlistStageDuration: 2 days,
            tokenURI: "https://test2.com/metadata/"
        });

        address collection1 = erc721Factory.createERC721Collection(params1);
        address collection2 = erc721Factory.createERC721Collection(params2);

        ERC721Collection col1 = ERC721Collection(collection1);
        ERC721Collection col2 = ERC721Collection(collection2);

        // Verify first collection
        assertEq(col1.name(), "First Collection");
        assertEq(col1.symbol(), "FC");

        // Verify second collection
        assertEq(col2.name(), "Second Collection");
        assertEq(col2.symbol(), "SC");

        // Ensure they are different
        assertTrue(collection1 != collection2);
    }
}
