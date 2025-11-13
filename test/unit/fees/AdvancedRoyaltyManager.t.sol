// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/fees/AdvancedRoyaltyManager.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/common/Fee.sol";
import "test/utils/TestHelpers.sol";
import "src/errors/FeeErrors.sol";

contract AdvancedRoyaltyManagerTest is Test, TestHelpers {
    AdvancedRoyaltyManager public royaltyManager;
    MarketplaceAccessControl public accessControl;
    Fee public baseFeeContract;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public collection = makeAddr("collection");
    address public creator1 = makeAddr("creator1");
    address public creator2 = makeAddr("creator2");
    address public platform = makeAddr("platform");

    event AdvancedRoyaltySet(
        address indexed collection, uint256 totalRoyaltyBps, uint256 recipientCount, address updatedBy
    );

    event RoyaltyRecipientAdded(
        address indexed collection, address indexed recipient, uint256 basisPoints, string role
    );

    event RoyaltyDistributed(
        address indexed collection,
        uint256 indexed tokenId,
        uint256 salePrice,
        uint256 totalRoyalty,
        uint256 recipientCount
    );

    function setUp() public {
        // Deploy access control
        vm.startPrank(admin);
        accessControl = new MarketplaceAccessControl();

        // Deploy base fee contract
        baseFeeContract = new Fee(admin, 250); // 2.5% default royalty

        // Deploy royalty manager
        royaltyManager = new AdvancedRoyaltyManager(address(accessControl), address(baseFeeContract));

        vm.stopPrank();
    }

    function testSetAdvancedRoyalty() public {
        // Prepare recipients
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](2);

        recipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1,
            basisPoints: 300, // 3%
            role: "creator",
            isActive: true
        });

        recipients[1] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: platform,
            basisPoints: 200, // 2%
            role: "platform",
            isActive: true
        });

        vm.startPrank(admin);

        // Expect events
        vm.expectEmit(true, true, false, true);
        emit RoyaltyRecipientAdded(collection, creator1, 300, "creator");

        vm.expectEmit(true, true, false, true);
        emit RoyaltyRecipientAdded(collection, platform, 200, "platform");

        vm.expectEmit(true, false, false, true);
        emit AdvancedRoyaltySet(collection, 500, 2, admin);

        // Set advanced royalty
        royaltyManager.setAdvancedRoyalty(
            collection,
            recipients,
            false // Don't use ERC2981
        );

        // Verify royalty info
        (
            bool hasAdvancedRoyalty,
            uint256 totalRoyaltyBps,
            uint256 maxRoyaltyBps,
            bool useERC2981,
            bool allowOverrides,
            uint256 lastUpdated,
            address updatedBy
        ) = royaltyManager.advancedRoyalties(collection);

        assertTrue(hasAdvancedRoyalty);
        assertEq(totalRoyaltyBps, 500);
        assertEq(maxRoyaltyBps, 500);
        assertFalse(useERC2981);
        assertFalse(allowOverrides);
        assertEq(updatedBy, admin);
        assertGt(lastUpdated, 0);

        vm.stopPrank();
    }

    function testCalculateCustomRoyalty() public {
        // Set up royalty recipients
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](2);

        recipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1,
            basisPoints: 300, // 3%
            role: "creator",
            isActive: true
        });

        recipients[1] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator2,
            basisPoints: 200, // 2%
            role: "collaborator",
            isActive: true
        });

        vm.prank(admin);
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        // Calculate royalties for 1 ETH sale
        uint256 salePrice = 1 ether;
        (uint256 totalRoyalty, address[] memory recipientAddresses, uint256[] memory amounts) =
            royaltyManager.calculateAndDistributeRoyalties(
                collection,
                1, // tokenId
                salePrice
            );

        // Verify calculations
        assertEq(totalRoyalty, 0.05 ether); // 5% total
        assertEq(recipientAddresses.length, 2);
        assertEq(amounts.length, 2);

        assertEq(recipientAddresses[0], creator1);
        assertEq(amounts[0], 0.03 ether); // 3%

        assertEq(recipientAddresses[1], creator2);
        assertEq(amounts[1], 0.02 ether); // 2%
    }

    function testRoyaltyValidation() public {
        // Test invalid recipient (zero address)
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory invalidRecipients =
            new AdvancedRoyaltyManager.RoyaltyRecipient[](1);

        invalidRecipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: address(0), basisPoints: 300, role: "creator", isActive: true
        });

        vm.prank(admin);
        vm.expectRevert(Fee__InvalidOwner.selector); // Should revert due to zero address
        royaltyManager.setAdvancedRoyalty(collection, invalidRecipients, false);

        // Test excessive royalty
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory excessiveRecipients =
            new AdvancedRoyaltyManager.RoyaltyRecipient[](1);

        excessiveRecipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1,
            basisPoints: 1500, // 15% - exceeds 10% cap
            role: "creator",
            isActive: true
        });

        vm.prank(admin);
        vm.expectRevert(Fee__InvalidRoyaltyFee.selector); // Should revert due to excessive royalty
        royaltyManager.setAdvancedRoyalty(collection, excessiveRecipients, false);
    }

    function testAccessControl() public {
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](1);

        recipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1, basisPoints: 300, role: "creator", isActive: true
        });

        // Test unauthorized access
        vm.prank(user);
        vm.expectRevert(Fee__InvalidOwner.selector); // Should revert due to lack of admin role
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        // Test authorized access
        vm.prank(admin);
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        // Should succeed
        (bool hasAdvancedRoyalty,,,,,,) = royaltyManager.advancedRoyalties(collection);
        assertTrue(hasAdvancedRoyalty);
    }

    function testERC2981Support() public {
        // Test ERC2981 interface support
        assertTrue(royaltyManager.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(royaltyManager.supportsInterface(type(IERC165).interfaceId));

        // Test default royalty info
        (address receiver, uint256 royaltyAmount) = royaltyManager.royaltyInfo(1, 1 ether);
        assertEq(receiver, admin); // Should be owner
        assertEq(royaltyAmount, 0.025 ether); // 2.5% default
    }

    function testMultipleRecipients() public {
        // Test with maximum recipients
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](5);

        for (uint256 i = 0; i < 5; i++) {
            recipients[i] = AdvancedRoyaltyManager.RoyaltyRecipient({
                recipient: makeAddr(string(abi.encodePacked("recipient", i))),
                basisPoints: 100, // 1% each
                role: "creator",
                isActive: true
            });
        }

        vm.prank(admin);
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        // Calculate royalties
        (uint256 totalRoyalty, address[] memory recipientAddresses, uint256[] memory amounts) =
            royaltyManager.calculateAndDistributeRoyalties(collection, 1, 1 ether);

        assertEq(totalRoyalty, 0.05 ether); // 5% total
        assertEq(recipientAddresses.length, 5);

        for (uint256 i = 0; i < 5; i++) {
            assertEq(amounts[i], 0.01 ether); // 1% each
        }
    }

    function testInactiveRecipients() public {
        // Set up recipients with one inactive
        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](2);

        recipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1, basisPoints: 300, role: "creator", isActive: true
        });

        recipients[1] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator2,
            basisPoints: 200,
            role: "collaborator",
            isActive: false // Inactive
        });

        vm.prank(admin);
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        // Calculate royalties - should only include active recipients
        (uint256 totalRoyalty, address[] memory recipientAddresses, uint256[] memory amounts) =
            royaltyManager.calculateAndDistributeRoyalties(collection, 1, 1 ether);

        assertEq(totalRoyalty, 0.03 ether); // Only 3% from active recipient
        assertEq(recipientAddresses.length, 1);
        assertEq(recipientAddresses[0], creator1);
        assertEq(amounts[0], 0.03 ether);
    }

    function testFuzzRoyaltyCalculation(uint256 salePrice, uint16 basisPoints) public {
        // Bound inputs to reasonable ranges
        salePrice = bound(salePrice, 0.001 ether, 1000 ether);
        basisPoints = uint16(bound(basisPoints, 1, 500)); // 0.01% to 5% (max single recipient)

        AdvancedRoyaltyManager.RoyaltyRecipient[] memory recipients = new AdvancedRoyaltyManager.RoyaltyRecipient[](1);

        recipients[0] = AdvancedRoyaltyManager.RoyaltyRecipient({
            recipient: creator1, basisPoints: basisPoints, role: "creator", isActive: true
        });

        vm.prank(admin);
        royaltyManager.setAdvancedRoyalty(collection, recipients, false);

        (uint256 totalRoyalty, address[] memory recipientAddresses, uint256[] memory amounts) =
            royaltyManager.calculateAndDistributeRoyalties(collection, 1, salePrice);

        uint256 expectedRoyalty = (salePrice * basisPoints) / 10000;

        assertEq(totalRoyalty, expectedRoyalty);
        assertEq(recipientAddresses.length, 1);
        assertEq(amounts[0], expectedRoyalty);
    }
}
