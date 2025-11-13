// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/libraries/FeeCalculationLib.sol";

/**
 * @title FeeCalculationLibTest
 * @notice Comprehensive tests for FeeCalculationLib
 */
contract FeeCalculationLibTest is Test {
    using FeeCalculationLib for uint256;

    uint256 constant BPS_DENOMINATOR = 10000;

    // Test wrapper contract to expose library functions
    TestWrapper wrapper;

    function setUp() public {
        wrapper = new TestWrapper();
    }

    // ============================================================================
    // PERCENTAGE FEE TESTS
    // ============================================================================

    function testCalculatePercentageFee_Success() public {
        uint256 amount = 1 ether;
        uint256 bps = 250; // 2.5%

        uint256 fee = FeeCalculationLib.calculatePercentageFee(amount, bps);

        assertEq(fee, 0.025 ether); // 2.5% of 1 ETH
    }

    function testCalculatePercentageFee_ZeroAmount() public {
        uint256 fee = FeeCalculationLib.calculatePercentageFee(0, 250);
        assertEq(fee, 0);
    }

    function testCalculatePercentageFee_ZeroBps() public {
        uint256 fee = FeeCalculationLib.calculatePercentageFee(1 ether, 0);
        assertEq(fee, 0);
    }

    function testCalculatePercentageFee_MaxBps() public {
        uint256 amount = 1 ether;
        uint256 fee = FeeCalculationLib.calculatePercentageFee(amount, BPS_DENOMINATOR);
        assertEq(fee, amount); // 100% fee
    }

    function testCalculatePercentageFee_RevertInvalidBps() public {
        vm.expectRevert(FeeCalculationLib.FeeCalculation__InvalidBasisPoints.selector);
        wrapper.calculatePercentageFee(1 ether, BPS_DENOMINATOR + 1);
    }

    // ============================================================================
    // TAKER FEE TESTS
    // ============================================================================

    function testCalculateTakerFee_Success() public {
        uint256 price = 1 ether;
        uint256 takerFeeBps = 200; // 2%

        uint256 fee = FeeCalculationLib.calculateTakerFee(price, takerFeeBps);

        assertEq(fee, 0.02 ether);
    }

    // ============================================================================
    // MARKETPLACE FEE TESTS
    // ============================================================================

    function testCalculateMarketplaceFee_Success() public {
        uint256 amount = 10 ether;
        uint256 marketplaceFeeBps = 250; // 2.5%

        uint256 fee = FeeCalculationLib.calculateMarketplaceFee(amount, marketplaceFeeBps);

        assertEq(fee, 0.25 ether);
    }

    // ============================================================================
    // FEE BREAKDOWN TESTS
    // ============================================================================

    function testCalculateFeeBreakdown_Success() public {
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyBps = 500; // 5%

        FeeCalculationLib.FeeBreakdown memory breakdown =
            FeeCalculationLib.calculateFeeBreakdown(salePrice, platformFeeBps, royaltyBps);

        assertEq(breakdown.platformFee, 0.025 ether);
        assertEq(breakdown.royaltyFee, 0.05 ether);
        assertEq(breakdown.totalFees, 0.075 ether);
        assertEq(breakdown.netAmount, 0.925 ether);
    }

    function testCalculateFeeBreakdown_ZeroFees() public {
        uint256 salePrice = 1 ether;

        FeeCalculationLib.FeeBreakdown memory breakdown = FeeCalculationLib.calculateFeeBreakdown(salePrice, 0, 0);

        assertEq(breakdown.platformFee, 0);
        assertEq(breakdown.royaltyFee, 0);
        assertEq(breakdown.totalFees, 0);
        assertEq(breakdown.netAmount, salePrice);
    }

    function testCalculateFeeBreakdown_RevertFeesExceedAmount() public {
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 6000; // 60%
        uint256 royaltyBps = 5000; // 50%
        // Total = 110% > 100%

        vm.expectRevert(FeeCalculationLib.FeeCalculation__FeeExceedsAmount.selector);
        wrapper.calculateFeeBreakdown(salePrice, platformFeeBps, royaltyBps);
    }

    // ============================================================================
    // BUYER PRICE TESTS
    // ============================================================================

    function testCalculateBuyerPrice_Success() public {
        uint256 basePrice = 1 ether;
        uint256 takerFeeBps = 200; // 2%
        uint256 royaltyBps = 500; // 5%

        uint256 totalPrice = FeeCalculationLib.calculateBuyerPrice(basePrice, takerFeeBps, royaltyBps);

        // Base: 1 ETH
        // Taker fee: 0.02 ETH
        // Royalty: 0.05 ETH
        // Total: 1.07 ETH
        assertEq(totalPrice, 1.07 ether);
    }

    function testCalculateBuyerPrice_NoFees() public {
        uint256 basePrice = 1 ether;

        uint256 totalPrice = FeeCalculationLib.calculateBuyerPrice(basePrice, 0, 0);

        assertEq(totalPrice, basePrice);
    }

    // ============================================================================
    // SELLER NET TESTS
    // ============================================================================

    function testCalculateSellerNet_Success() public {
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyBps = 500; // 5%

        uint256 netAmount = FeeCalculationLib.calculateSellerNet(salePrice, platformFeeBps, royaltyBps);

        // Sale: 1 ETH
        // Platform fee: 0.025 ETH
        // Royalty: 0.05 ETH
        // Net: 0.925 ETH
        assertEq(netAmount, 0.925 ether);
    }

    function testCalculateSellerNet_RevertFeesExceed() public {
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 8000; // 80%
        uint256 royaltyBps = 3000; // 30%
        // Total = 110% > 100%

        vm.expectRevert(FeeCalculationLib.FeeCalculation__FeeExceedsAmount.selector);
        wrapper.calculateSellerNet(salePrice, platformFeeBps, royaltyBps);
    }

    // ============================================================================
    // UTILITY TESTS
    // ============================================================================

    function testPercentageToBps_Success() public {
        assertEq(FeeCalculationLib.percentageToBps(5), 500); // 5% = 500 bps
        assertEq(FeeCalculationLib.percentageToBps(10), 1000); // 10% = 1000 bps
        assertEq(FeeCalculationLib.percentageToBps(100), 10000); // 100% = 10000 bps
    }

    function testBpsToPercentage_Success() public {
        assertEq(FeeCalculationLib.bpsToPercentage(500), 5); // 500 bps = 5%
        assertEq(FeeCalculationLib.bpsToPercentage(1000), 10); // 1000 bps = 10%
        assertEq(FeeCalculationLib.bpsToPercentage(10000), 100); // 10000 bps = 100%
    }

    function testValidateFeeRate_Success() public {
        assertTrue(FeeCalculationLib.validateFeeRate(250, 1000)); // 2.5% <= 10%
        assertTrue(FeeCalculationLib.validateFeeRate(1000, 1000)); // 10% <= 10%
        assertFalse(FeeCalculationLib.validateFeeRate(1001, 1000)); // 10.01% > 10%
        assertFalse(FeeCalculationLib.validateFeeRate(10001, 5000)); // >100%
    }

    function testSumFees_Success() public {
        uint256[] memory fees = new uint256[](3);
        fees[0] = 0.01 ether;
        fees[1] = 0.02 ether;
        fees[2] = 0.03 ether;

        uint256 total = FeeCalculationLib.sumFees(fees);

        assertEq(total, 0.06 ether);
    }

    function testSumFees_EmptyArray() public {
        uint256[] memory fees = new uint256[](0);

        uint256 total = FeeCalculationLib.sumFees(fees);

        assertEq(total, 0);
    }

    function testSumFees_SingleFee() public {
        uint256[] memory fees = new uint256[](1);
        fees[0] = 1 ether;

        uint256 total = FeeCalculationLib.sumFees(fees);

        assertEq(total, 1 ether);
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    function testCalculatePercentageFee_LargeAmount() public {
        uint256 amount = 1000000 ether;
        uint256 bps = 250;

        uint256 fee = FeeCalculationLib.calculatePercentageFee(amount, bps);

        assertEq(fee, 25000 ether); // 2.5% of 1M ETH
    }

    function testCalculatePercentageFee_SmallAmount() public {
        uint256 amount = 1 wei;
        uint256 bps = 1; // 0.01%

        uint256 fee = FeeCalculationLib.calculatePercentageFee(amount, bps);

        assertEq(fee, 0); // Rounds down to 0
    }

    function testFeeBreakdown_MaxValidFees() public {
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 5000; // 50%
        uint256 royaltyBps = 5000; // 50%
        // Total = 100%

        FeeCalculationLib.FeeBreakdown memory breakdown =
            FeeCalculationLib.calculateFeeBreakdown(salePrice, platformFeeBps, royaltyBps);

        assertEq(breakdown.totalFees, salePrice);
        assertEq(breakdown.netAmount, 0);
    }
}

/**
 * @notice Wrapper contract to test library functions that revert
 */
contract TestWrapper {
    function calculatePercentageFee(uint256 amount, uint256 basisPoints) external pure returns (uint256) {
        return FeeCalculationLib.calculatePercentageFee(amount, basisPoints);
    }

    function calculateFeeBreakdown(uint256 salePrice, uint256 platformFeeBps, uint256 royaltyBps)
        external
        pure
        returns (FeeCalculationLib.FeeBreakdown memory)
    {
        return FeeCalculationLib.calculateFeeBreakdown(salePrice, platformFeeBps, royaltyBps);
    }

    function calculateSellerNet(uint256 salePrice, uint256 platformFeeBps, uint256 royaltyBps)
        external
        pure
        returns (uint256)
    {
        return FeeCalculationLib.calculateSellerNet(salePrice, platformFeeBps, royaltyBps);
    }
}
