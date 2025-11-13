// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/fees/AdvancedFeeManager.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import {FeeConfig, UserVolumeData, FeeTier, CollectionFeeOverride, VIPStatus} from "src/types/FeeTypes.sol";
import "src/errors/FeeErrors.sol";

contract AdvancedFeeManagerTest is Test {
    AdvancedFeeManager public feeManager;
    MarketplaceAccessControl public accessControl;

    address public owner = address(0x1);
    address public feeRecipient = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public collection1 = address(0x5);
    address public collection2 = address(0x6);
    address public operator = address(0x7);
    address public admin = address(0x8);

    event FeeConfigUpdated(
        uint256 oldMakerFee, uint256 newMakerFee, uint256 oldTakerFee, uint256 newTakerFee, address updatedBy
    );

    event FeeTierUpdated(address indexed user, uint256 oldTierId, uint256 newTierId, uint256 newDiscountBps);

    event UserVolumeUpdated(
        address indexed user, uint256 newTotalVolume, uint256 newLast30DaysVolume, uint256 tradeCount
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy access control
        accessControl = new MarketplaceAccessControl();

        // Deploy fee manager
        feeManager = new AdvancedFeeManager(address(accessControl), feeRecipient);

        // Grant roles
        accessControl.grantRoleSimple(accessControl.OPERATOR_ROLE(), operator);

        accessControl.grantRoleSimple(accessControl.ADMIN_ROLE(), admin);

        vm.stopPrank();
    }

    function testInitialConfiguration() public {
        // Check initial fee configuration
        FeeConfig memory config = feeManager.getBaseFeeConfig();

        assertEq(config.makerFee, 250); // 2.5%
        assertEq(config.takerFee, 250); // 2.5%
        assertEq(config.listingFee, 0);
        assertEq(config.auctionFee, 50); // 0.5%
        assertEq(config.bundleFee, 100); // 1%
        assertTrue(config.isActive);

        // Check fee recipient
        assertEq(feeManager.feeRecipient(), feeRecipient);

        // Check initial tier count
        assertEq(feeManager.getFeeTierCount(), 4);
    }

    function testCalculateBaseFees() public {
        uint256 salePrice = 1 ether;

        // Test maker fee calculation
        (uint256 makerFee, uint256 discount) =
            feeManager.calculateFees(
                user1,
                collection1,
                salePrice,
                true // isMaker
            );

        // Should be 2.5% of 1 ether = 0.025 ether
        assertEq(makerFee, 0.025 ether);
        assertEq(discount, 0); // No discount for new user

        // Test taker fee calculation
        (uint256 takerFee, uint256 takerDiscount) =
            feeManager.calculateFees(
                user1,
                collection1,
                salePrice,
                false // isTaker
            );

        assertEq(takerFee, 0.025 ether);
        assertEq(takerDiscount, 0);
    }

    function testUpdateUserVolume() public {
        vm.startPrank(operator);

        uint256 tradeVolume = 5 ether;

        // Update user volume
        feeManager.updateUserVolume(user1, tradeVolume);

        // Check volume data
        UserVolumeData memory volumeData = feeManager.getUserVolumeData(user1);
        assertEq(volumeData.totalVolume, tradeVolume);
        assertEq(volumeData.tradeCount, 1);
        assertEq(volumeData.last30DaysVolume, tradeVolume);

        // Check fee tier (should still be Bronze - tier 0)
        FeeTier memory tier = feeManager.getUserFeeTier(user1);
        assertEq(tier.tierId, 0);
        assertEq(tier.discountBps, 0);

        vm.stopPrank();
    }

    function testFeeTierUpgrade() public {
        vm.startPrank(operator);

        // Update user volume to Silver tier (10+ ETH)
        feeManager.updateUserVolume(user1, 15 ether);

        // Check tier upgrade
        FeeTier memory tier = feeManager.getUserFeeTier(user1);
        assertEq(tier.tierId, 1); // Silver tier
        assertEq(tier.discountBps, 50); // 0.5% discount

        // Test fee calculation with discount
        (uint256 fee, uint256 discount) = feeManager.calculateFees(user1, collection1, 1 ether, true);

        // Base fee: 0.025 ether, discount: 0.5% = 0.000125 ether
        // Final fee: 0.025 - 0.000125 = 0.024875 ether
        assertEq(fee, 0.024875 ether);
        assertEq(discount, 50);

        vm.stopPrank();
    }

    function testCollectionFeeOverride() public {
        vm.startPrank(admin);

        // Set collection override
        CollectionFeeOverride memory feeOverride = CollectionFeeOverride({
            makerFeeOverride: 200, // 2% instead of 2.5%
            takerFeeOverride: 200,
            discountBps: 25, // Additional 0.25% discount
            hasOverride: true,
            isVerified: true, // Additional 0.5% discount for verified
            setAt: block.timestamp
        });

        feeManager.setCollectionFeeOverride(collection1, feeOverride);

        // Test fee calculation with override
        (uint256 fee, uint256 discount) = feeManager.calculateFees(user1, collection1, 1 ether, true);

        // Override fee: 2% = 0.02 ether
        // Collection discount: 0.25% + 0.5% (verified) = 0.75% = 75 bps
        // Total discount on 0.02 ether = 0.00015 ether
        // Final fee: 0.02 - 0.00015 = 0.01985 ether
        assertEq(fee, 0.01985 ether);

        vm.stopPrank();
    }

    function testVIPStatus() public {
        vm.startPrank(admin);

        // Set VIP status
        VIPStatus memory vipData = VIPStatus({
            isVIP: true,
            vipDiscountBps: 100, // 1% VIP discount
            vipExpiryTimestamp: block.timestamp + 30 days,
            vipTier: "Gold"
        });

        feeManager.updateVIPStatus(user1, vipData);

        // Test fee calculation with VIP discount
        (uint256 fee, uint256 discount) = feeManager.calculateFees(user1, collection1, 1 ether, true);

        // Base fee: 0.025 ether
        // VIP discount: 1% = 100 bps
        // Final fee: 0.025 - (0.025 * 100 / 10000) = 0.025 - 0.00025 = 0.02475 ether
        assertEq(fee, 0.02475 ether);
        assertEq(discount, 100);

        vm.stopPrank();
    }

    function testUpdateBaseFeeConfig() public {
        vm.startPrank(admin);

        FeeConfig memory newConfig = FeeConfig({
            makerFee: 300, // 3%
            takerFee: 200, // 2%
            listingFee: 0.001 ether,
            auctionFee: 75, // 0.75%
            bundleFee: 125, // 1.25%
            isActive: true
        });

        vm.expectEmit(true, true, true, true);
        emit FeeConfigUpdated(250, 300, 250, 200, admin);

        feeManager.updateBaseFeeConfig(newConfig);

        // Verify update
        FeeConfig memory config = feeManager.getBaseFeeConfig();
        assertEq(config.makerFee, 300);
        assertEq(config.takerFee, 200);
        assertEq(config.listingFee, 0.001 ether);

        vm.stopPrank();
    }

    function testBatchUpdateUserVolumes() public {
        vm.startPrank(admin);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory volumes = new uint256[](2);
        volumes[0] = 25 ether; // Silver tier (10-50 ETH)
        volumes[1] = 100 ether; // Gold tier (50+ ETH)

        feeManager.batchUpdateUserVolumes(users, volumes);

        // Check user1 tier (25 ETH = Silver tier)
        FeeTier memory tier1 = feeManager.getUserFeeTier(user1);
        assertEq(tier1.tierId, 1); // Silver tier
        assertEq(tier1.discountBps, 50); // 0.5% discount

        // Check user2 tier (100 ETH = Gold tier)
        FeeTier memory tier2 = feeManager.getUserFeeTier(user2);
        assertEq(tier2.tierId, 2); // Gold tier
        assertEq(tier2.discountBps, 100); // 1% discount

        vm.stopPrank();
    }

    function testGetEffectiveFeeRate() public {
        vm.startPrank(operator);

        // Set user to Gold tier
        feeManager.updateUserVolume(user1, 60 ether);

        vm.stopPrank();

        // Get effective fee rate
        uint256 effectiveRate = feeManager.getEffectiveFeeRate(user1, collection1, true);

        // Base rate: 250 bps, Gold discount: 100 bps
        // Effective rate: 250 - (250 * 100 / 10000) = 250 - 2.5 = 247.5 bps (rounded to 248)
        assertEq(effectiveRate, 248);
    }

    function testCheckTierUpgradeEligibility() public {
        vm.startPrank(operator);

        // Set user to Silver tier (15 ETH) - not enough for Gold yet
        feeManager.updateUserVolume(user1, 15 ether);

        vm.stopPrank();

        // Check upgrade eligibility - should NOT be able to upgrade yet
        (bool canUpgrade, uint256 nextTierId, uint256 volumeNeeded) = feeManager.checkTierUpgradeEligibility(user1);

        assertFalse(canUpgrade); // Can't upgrade yet, needs more volume
        assertEq(nextTierId, 2); // Gold tier
        assertEq(volumeNeeded, 35 ether); // Need 50 ETH total, has 15 ETH

        // Now test with enough volume for upgrade
        vm.startPrank(operator);
        feeManager.updateUserVolume(user1, 35 ether); // Total now 50 ETH
        vm.stopPrank();

        (canUpgrade, nextTierId, volumeNeeded) = feeManager.checkTierUpgradeEligibility(user1);

        assertFalse(canUpgrade); // Still can't upgrade to Platinum (needs 200 ETH total)
        assertEq(nextTierId, 3); // Platinum tier
        assertEq(volumeNeeded, 150 ether); // Need 200 ETH total, has 50 ETH
    }

    function testAccessControl() public {
        // Test unauthorized access
        vm.startPrank(user1);

        vm.expectRevert(Fee__InvalidOwner.selector);
        feeManager.updateUserVolume(user2, 1 ether);

        vm.stopPrank();

        // Test authorized access
        vm.startPrank(operator);

        // Should not revert
        feeManager.updateUserVolume(user2, 1 ether);

        vm.stopPrank();
    }

    function testInvalidFeeParams() public {
        vm.startPrank(admin);

        FeeConfig memory invalidConfig = FeeConfig({
            makerFee: 1500, // 15% - too high
            takerFee: 200,
            listingFee: 0,
            auctionFee: 50,
            bundleFee: 100,
            isActive: true
        });

        vm.expectRevert(Fee__InvalidRoyaltyFee.selector);
        feeManager.updateBaseFeeConfig(invalidConfig);

        vm.stopPrank();
    }
}
