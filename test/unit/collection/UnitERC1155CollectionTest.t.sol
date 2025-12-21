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
        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();
        vm.deal(setup.user, setup.params.allowlistMintPrice);

        vm.startPrank(setup.user);
        vm.expectRevert(Collection__NotInAllowlist.selector);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_Allowlist() public {
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

    // ============ Owner Minting Tests ============

    function test_OwnerMint_Success() public {
        // Owner can mint without payment, before mint start time
        vm.startPrank(setup.owner);
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(setup.owner, 1);
        setup.collection.ownerMint(setup.owner, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.owner, 1), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
    }

    function test_OwnerMint_ToOtherAddress() public {
        // Owner can mint to another address
        vm.startPrank(setup.owner);
        setup.collection.ownerMint(setup.user, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.user, 1), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
    }

    function test_OwnerMint_BatchSuccess() public {
        vm.startPrank(setup.owner);
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(setup.owner, 5);
        setup.collection.ownerMint(setup.owner, 5);
        vm.stopPrank();

        for (uint256 i = 1; i <= 5; i++) {
            assertEq(setup.collection.balanceOf(setup.owner, i), 1);
        }
        assertEq(setup.collection.getTotalMinted(), 5);
    }

    function test_OwnerMint_BypassesMintLimitPerWallet() public {
        // Owner should be able to exceed mintLimitPerWallet
        vm.startPrank(setup.owner);
        // mintLimitPerWallet is 5, but owner can mint more
        setup.collection.ownerMint(setup.owner, 10);
        vm.stopPrank();

        assertEq(setup.collection.getTotalMinted(), 10);
    }

    function test_OwnerMint_BypassesAllowlist() public {
        // Set allowlist-only mode
        vm.startPrank(setup.owner);
        setup.collection.setAllowlistOnly(true);
        // Owner can still mint without being in allowlist
        setup.collection.ownerMint(setup.owner, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.owner, 1), 1);
    }

    function test_OwnerMint_BeforeMintStart() public {
        // Owner can mint before mintStartTime
        vm.warp(setup.params.mintStartTime - 1 days);

        vm.startPrank(setup.owner);
        setup.collection.ownerMint(setup.owner, 1);
        vm.stopPrank();

        assertEq(setup.collection.balanceOf(setup.owner, 1), 1);
    }

    function test_OwnerMint_RespectsMaxSupply() public {
        // Create collection with low max supply
        CollectionParams memory smallParams = setup.params;
        smallParams.maxSupply = 5;
        ERC1155Collection smallCollection = new ERC1155Collection(smallParams);

        vm.startPrank(setup.owner);
        // Mint up to max
        smallCollection.ownerMint(setup.owner, 5);

        // Try to mint more - should fail
        vm.expectRevert(Collection__MintLimitExceeded.selector);
        smallCollection.ownerMint(setup.owner, 1);
        vm.stopPrank();
    }

    function test_OwnerMint_OnlyOwner() public {
        vm.startPrank(setup.user);
        vm.expectRevert();
        setup.collection.ownerMint(setup.user, 1);
        vm.stopPrank();
    }

    function test_OwnerMint_ZeroAmount() public {
        vm.startPrank(setup.owner);
        vm.expectRevert(Collection__InvalidAmount.selector);
        setup.collection.ownerMint(setup.owner, 0);
        vm.stopPrank();
    }
}
