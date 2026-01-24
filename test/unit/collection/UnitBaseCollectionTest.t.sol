// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";
import "src/errors/CollectionErrors.sol";
import {MintStage} from "src/types/ListingTypes.sol";

contract MockBaseCollection is BaseCollection {
    constructor(CollectionParams memory params) BaseCollection(params) {}

    function mint(address to, uint256 amount) external payable {
        uint256 requiredPayment = checkMint(to, amount);
        if (msg.value < requiredPayment) {
            revert Collection__InsufficientPayment();
        }
        s_mintedPerWallet[to] += amount;
        s_totalMinted += amount;
    }
}

contract UnitBaseCollectionTest is Test {
    struct TestSetup {
        MockBaseCollection collection;
        CollectionParams params;
        address owner;
        address user;
        address user2;
    }

    TestSetup private setup;

    function setUp() public {
        setup.owner = makeAddr("owner");
        setup.user = makeAddr("user");
        setup.user2 = makeAddr("user2");

        setup.params = CollectionParams({
            name: "Test Collection",
            symbol: "TEST",
            owner: setup.owner,
            description: "Test Description",
            mintPrice: 0.1 ether,
            royaltyFee: 500, // 5%
            maxSupply: 1000,
            mintLimitPerWallet: 5,
            mintStartTime: block.timestamp + 1 days,
            allowlistMintPrice: 0.08 ether,
            publicMintPrice: 0.1 ether,
            allowlistStageDuration: 1 days,
            tokenURI: "ipfs://test/"
        });

        vm.startPrank(setup.owner);
        setup.collection = new MockBaseCollection(setup.params);
        vm.stopPrank();
    }

    function test_Constructor_Initialization() public {
        assertEq(setup.collection.getDescription(), setup.params.description);
        assertEq(setup.collection.getMintPrice(), setup.params.mintPrice);
        assertEq(setup.collection.getMaxSupply(), setup.params.maxSupply);
        assertEq(setup.collection.getMintLimitPerWallet(), setup.params.mintLimitPerWallet);
        assertEq(setup.collection.getMintStartTime(), setup.params.mintStartTime);
        assertEq(setup.collection.getAllowlistMintPrice(), setup.params.allowlistMintPrice);
        assertEq(setup.collection.getPublicMintPrice(), setup.params.publicMintPrice);
        assertEq(
            setup.collection.getAllowlistStageEnd(), setup.params.mintStartTime + setup.params.allowlistStageDuration
        );
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.INACTIVE));
    }

    function test_AddToAllowlist() public {
        address[] memory addresses = new address[](2);
        addresses[0] = setup.user;
        addresses[1] = setup.user2;

        vm.startPrank(setup.owner);
        setup.collection.addToAllowlist(addresses);
        assertTrue(setup.collection.isInAllowlist(setup.user));
        assertTrue(setup.collection.isInAllowlist(setup.user2));
        vm.stopPrank();
    }

    function test_AddToAllowlist_NotOwner() public {
        address[] memory addresses = new address[](1);
        addresses[0] = setup.user;

        vm.startPrank(setup.user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", setup.user));
        setup.collection.addToAllowlist(addresses);
        vm.stopPrank();
    }

    function test_UpdateMintStage_Initial() public {
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.INACTIVE));
    }

    function test_UpdateMintStage_Allowlist() public {
        // Enable allowlist-only mode to test allowlist stage
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.ALLOWLIST));
    }

    function test_UpdateMintStage_Public() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.PUBLIC));
    }

    function test_Mint_BeforeStartTime() public {
        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.publicMintPrice);
        setup.collection.updateMintStage(); // Update stage first
        vm.expectRevert(Collection__MintingNotActive.selector);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_ExceedMaxSupply() public {
        // Move to public stage
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();

        // Create and fund multiple users
        uint256 usersNeeded =
            (setup.params.maxSupply + setup.params.mintLimitPerWallet - 1) / setup.params.mintLimitPerWallet;
        address[] memory users = new address[](usersNeeded);

        for (uint256 i = 0; i < usersNeeded; i++) {
            users[i] = makeAddr(string.concat("user", vm.toString(i)));
            vm.deal(users[i], setup.params.publicMintPrice * setup.params.mintLimitPerWallet);
        }

        // Let each user mint up to their wallet limit
        for (uint256 i = 0; i < usersNeeded - 1; i++) {
            vm.startPrank(users[i]);
            for (uint256 j = 0; j < setup.params.mintLimitPerWallet; j++) {
                setup.collection.mint{value: setup.params.publicMintPrice}(users[i], 1);
            }
            vm.stopPrank();
        }

        // Last user mints remaining tokens
        uint256 remainingTokens = setup.params.maxSupply - (usersNeeded - 1) * setup.params.mintLimitPerWallet;
        vm.startPrank(users[usersNeeded - 1]);
        for (uint256 i = 0; i < remainingTokens; i++) {
            setup.collection.mint{value: setup.params.publicMintPrice}(users[usersNeeded - 1], 1);
        }
        vm.stopPrank();

        // Verify total minted equals max supply
        assertEq(setup.collection.getTotalMinted(), setup.params.maxSupply);

        // Try to mint one more with a new user, which should fail due to max supply
        address newUser = makeAddr("newUser");
        vm.deal(newUser, setup.params.publicMintPrice);
        vm.startPrank(newUser);
        vm.expectRevert(Collection__MintLimitExceeded.selector);
        setup.collection.mint{value: setup.params.publicMintPrice}(newUser, 1);
        vm.stopPrank();
    }

    function test_Mint_Allowlist_NotInAllowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();

        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.allowlistMintPrice);
        vm.expectRevert(Collection__NotInAllowlist.selector);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Mint_Allowlist_Success() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        vm.warp(setup.params.mintStartTime);
        setup.collection.updateMintStage();

        // Add user to allowlist
        address[] memory addresses = new address[](1);
        addresses[0] = setup.user;
        vm.startPrank(setup.owner);
        setup.collection.addToAllowlist(addresses);
        vm.stopPrank();

        // Mint with allowlist price
        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.allowlistMintPrice);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.user), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
        vm.stopPrank();
    }

    function test_Mint_Public_Success() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();

        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.publicMintPrice);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.user), 1);
        assertEq(setup.collection.getTotalMinted(), 1);
        vm.stopPrank();
    }

    function test_Mint_ZeroAmount() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();

        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.publicMintPrice);
        vm.expectRevert(Collection__InvalidAmount.selector);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.user, 0);
        vm.stopPrank();
    }

    function test_Mint_InsufficientPayment() public {
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();

        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.publicMintPrice - 0.01 ether);
        vm.expectRevert(Collection__InsufficientPayment.selector);
        setup.collection.mint{value: setup.params.publicMintPrice - 0.01 ether}(setup.user, 1);
        vm.stopPrank();
    }

    // ============ Owner Allowlist Exemption Tests ============

    function test_Owner_MintDuringAllowlist_NotOnAllowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        // Warp to allowlist stage
        vm.warp(setup.params.mintStartTime + 100);
        setup.collection.updateMintStage();
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.ALLOWLIST));

        // Owner NOT on allowlist
        assertFalse(setup.collection.isInAllowlist(setup.owner));

        // Owner should still be able to mint
        vm.startPrank(setup.owner);
        vm.deal(setup.owner, setup.params.allowlistMintPrice);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
        vm.stopPrank();
    }

    function test_Owner_MintDuringAllowlist_WithAllowlistEntry() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        // Warp to allowlist stage
        vm.warp(setup.params.mintStartTime + 100);
        setup.collection.updateMintStage();

        // Add owner to allowlist (should still work)
        address[] memory addresses = new address[](1);
        addresses[0] = setup.owner;
        vm.prank(setup.owner);
        setup.collection.addToAllowlist(addresses);

        // Owner should be able to mint
        vm.startPrank(setup.owner);
        vm.deal(setup.owner, setup.params.allowlistMintPrice);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
        vm.stopPrank();
    }

    function test_NonOwner_MintDuringAllowlist_WhileOwnerOnAllowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        // Warp to allowlist stage
        vm.warp(setup.params.mintStartTime + 100);
        setup.collection.updateMintStage();

        // Add only owner to allowlist
        address[] memory addresses = new address[](1);
        addresses[0] = setup.owner;
        vm.prank(setup.owner);
        setup.collection.addToAllowlist(addresses);

        // Non-owner should NOT be able to mint (no piggybacking on owner exemption)
        vm.startPrank(setup.user);
        vm.deal(setup.user, setup.params.allowlistMintPrice);
        vm.expectRevert(Collection__NotInAllowlist.selector);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
        vm.stopPrank();
    }

    function test_Owner_MintDuringPublicStage() public {
        // Warp to public stage
        vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
        setup.collection.updateMintStage();
        assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.PUBLIC));

        // Owner should be able to mint during public stage
        vm.startPrank(setup.owner);
        vm.deal(setup.owner, setup.params.publicMintPrice);
        setup.collection.mint{value: setup.params.publicMintPrice}(setup.owner, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
        vm.stopPrank();
    }

    function test_Owner_MintAllowlistOnlyMode_NotOnAllowlist() public {
        // Enable allowlist-only mode
        vm.prank(setup.owner);
        setup.collection.setAllowlistOnly(true);

        // Warp to allowlist stage
        vm.warp(setup.params.mintStartTime + 100);
        setup.collection.updateMintStage();

        // Owner NOT on allowlist
        assertFalse(setup.collection.isInAllowlist(setup.owner));

        // Owner should still be able to mint in allowlist-only mode
        vm.startPrank(setup.owner);
        vm.deal(setup.owner, setup.params.allowlistMintPrice);
        setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
        assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
        vm.stopPrank();
    }
}
