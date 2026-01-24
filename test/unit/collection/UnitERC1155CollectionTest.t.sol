// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1155Collection} from "src/core/collection/ERC1155Collection.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";
import {Minted, BatchMinted} from "src/events/CollectionEvents.sol";
import "src/errors/CollectionErrors.sol";
import {MintStage} from "src/types/ListingTypes.sol";

contract UnitERC1155CollectionTest is Test {
    struct TestSetup {
        ERC1155Collection collection;
        CollectionParams params;
        address owner;
        address user;
    }

    TestSetup private setup;

    function setUp() public {
        setup.owner = makeAddr("owner");
        setup.user = makeAddr("user");
        vm.startPrank(setup.owner);
        setup.params = CollectionParams({
            owner: setup.owner,
            name: "Test Collection",
            symbol: "TEST",
            description: "Test Description",
            tokenURI: "ipfs://test",
            mintPrice: 0.1 ether,
            maxSupply: 1000,
            mintLimitPerWallet: 5,
            mintStartTime: block.timestamp + 1 days,
            allowlistMintPrice: 0.08 ether,
            publicMintPrice: 0.1 ether,
            allowlistStageDuration: 1 days,
            royaltyFee: 250 // 2.5%
        });
        setup.collection = new ERC1155Collection(setup.params);
        vm.stopPrank();
    }

    function test_Mint() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.publicMintPrice);

        vm.startPrank(setup.user);
        vm.expectEmit(true, true, true, true);
        emit Minted(setup.user, 1, 1);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.user, 1), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
        assertEq(setup.collection.getMintedPerWallet(setup.user), 1);
    }

    function test_BatchMint() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.publicMintPrice * 3);

        vm.startPrank(setup.user);
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(setup.user, 3);
        setup.collection.batchMintERC1155{value: setup.params.publicMintPrice * 3}(setup.user, 3);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.user, 1), 1);
        assertEq(setup.collection.balanceOf(setup.user, 2), 1);
        assertEq(setup.collection.balanceOf(setup.user, 3), 1);
        assertEq(setup.collection.getTotalMinted(), 3);
        assertEq(setup.collection.getMintedPerWallet(setup.user), 3);
    }

    function test_TokenURI() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.publicMintPrice);

        vm.startPrank(setup.user);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        vm.stopPrank();

        assertEq(setup.collection.uri(1), setup.params.tokenURI);
    }

    function test_SupportsInterface() public {
        assertTrue(setup.collection.supportsInterface(0xd9b67a26));
        assertTrue(setup.collection.supportsInterface(0x0e89341c));
        assertTrue(setup.collection.supportsInterface(0x2a55205a));
        assertFalse(setup.collection.supportsInterface(0x12345678));
    }

    function test_Mint_InsufficientPayment() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.publicMintPrice - 1);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__InsufficientPayment.selector);
        setup.collection.mint{value: setup.params.publicMintPrice - 1}(setup.user, 1);
        vm.stopPrank();
    }

    function test_BatchMint_InsufficientPayment() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.publicMintPrice * 3 - 1);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__InsufficientPayment.selector);
        setup.collection.batchMintERC1155{value: setup.params.publicMintPrice * 3 - 1}(setup.user, 3);
        vm.stopPrank();
    }

    function test_Mint_NotStarted() public {
        vm.deal(setup.user, setup.params.publicMintPrice);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__MintingNotActive.selector);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_NotActive() public {
        vm.warp(setup.params.mintStartTime - 1);
        vm.deal(setup.user, setup.params.publicMintPrice);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__MintingNotActive.selector);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_NotInAllowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.allowlistMintPrice);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__NotInAllowlist.selector);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_Allowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.allowlistMintPrice);

        vm.startPrank(setup.owner);
        address[] memory addresses = new address[](1);
        addresses[0] = setup.user;
        setup.collection.addToAllowlist(addresses);
        vm.stopPrank();

        vm.startPrank(setup.user);
        vm.expectEmit(true, true, true, true);
        emit Minted(setup.user, 1, 1);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.user, 1), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
        assertEq(setup.collection.getMintedPerWallet(setup.user), 1);
    }
}
