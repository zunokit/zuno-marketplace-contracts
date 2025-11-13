// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title FeeCalculationLib
 * @notice Library for standardized fee calculations across the marketplace
 * @dev Provides common fee calculation utilities to reduce code duplication
 */
library FeeCalculationLib {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    uint256 public constant BPS_DENOMINATOR = 10000; // 100% = 10000 basis points

    // ============================================================================
    // ERRORS
    // ============================================================================

    error FeeCalculation__InvalidBasisPoints();
    error FeeCalculation__FeeExceedsAmount();

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Fee breakdown structure
     */
    struct FeeBreakdown {
        uint256 platformFee;
        uint256 royaltyFee;
        uint256 totalFees;
        uint256 netAmount; // Amount after fees
    }

    // ============================================================================
    // CORE FEE CALCULATIONS
    // ============================================================================

    /**
     * @notice Calculates percentage of an amount using basis points
     * @param amount Base amount
     * @param basisPoints Percentage in basis points (100 = 1%, 10000 = 100%)
     * @return feeAmount Calculated fee amount
     */
    function calculatePercentageFee(uint256 amount, uint256 basisPoints) internal pure returns (uint256 feeAmount) {
        if (basisPoints > BPS_DENOMINATOR) {
            revert FeeCalculation__InvalidBasisPoints();
        }
        return (amount * basisPoints) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates taker fee (buyer pays)
     * @param price Sale price
     * @param takerFeeBps Taker fee in basis points
     * @return takerFee Calculated taker fee
     */
    function calculateTakerFee(uint256 price, uint256 takerFeeBps) internal pure returns (uint256 takerFee) {
        return calculatePercentageFee(price, takerFeeBps);
    }

    /**
     * @notice Calculates marketplace fee (platform fee)
     * @param amount Transaction amount
     * @param marketplaceFeeBps Marketplace fee in basis points
     * @return marketplaceFee Calculated marketplace fee
     */
    function calculateMarketplaceFee(uint256 amount, uint256 marketplaceFeeBps)
        internal
        pure
        returns (uint256 marketplaceFee)
    {
        return calculatePercentageFee(amount, marketplaceFeeBps);
    }

    /**
     * @notice Calculates complete fee breakdown
     * @param salePrice Sale price of the item
     * @param platformFeeBps Platform fee in basis points
     * @param royaltyBps Royalty fee in basis points
     * @return breakdown Complete fee breakdown
     */
    function calculateFeeBreakdown(uint256 salePrice, uint256 platformFeeBps, uint256 royaltyBps)
        internal
        pure
        returns (FeeBreakdown memory breakdown)
    {
        breakdown.platformFee = calculatePercentageFee(salePrice, platformFeeBps);
        breakdown.royaltyFee = calculatePercentageFee(salePrice, royaltyBps);
        breakdown.totalFees = breakdown.platformFee + breakdown.royaltyFee;

        // Ensure fees don't exceed sale price
        if (breakdown.totalFees > salePrice) {
            revert FeeCalculation__FeeExceedsAmount();
        }

        breakdown.netAmount = salePrice - breakdown.totalFees;
        return breakdown;
    }

    /**
     * @notice Calculates buyer's total payment (price + fees)
     * @param basePrice Base price of the item
     * @param takerFeeBps Taker fee in basis points
     * @param royaltyBps Royalty in basis points
     * @return totalPrice Total amount buyer needs to pay
     */
    function calculateBuyerPrice(uint256 basePrice, uint256 takerFeeBps, uint256 royaltyBps)
        internal
        pure
        returns (uint256 totalPrice)
    {
        uint256 takerFee = calculatePercentageFee(basePrice, takerFeeBps);
        uint256 royalty = calculatePercentageFee(basePrice, royaltyBps);
        return basePrice + takerFee + royalty;
    }

    /**
     * @notice Calculates seller's net amount after fees
     * @param salePrice Sale price
     * @param platformFeeBps Platform fee in basis points
     * @param royaltyBps Royalty in basis points
     * @return netAmount Amount seller receives
     */
    function calculateSellerNet(uint256 salePrice, uint256 platformFeeBps, uint256 royaltyBps)
        internal
        pure
        returns (uint256 netAmount)
    {
        uint256 platformFee = calculatePercentageFee(salePrice, platformFeeBps);
        uint256 royalty = calculatePercentageFee(salePrice, royaltyBps);
        uint256 totalFees = platformFee + royalty;

        if (totalFees > salePrice) {
            revert FeeCalculation__FeeExceedsAmount();
        }

        return salePrice - totalFees;
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Converts percentage to basis points
     * @param percentage Percentage (e.g., 5 for 5%)
     * @return basisPoints Equivalent in basis points
     */
    function percentageToBps(uint256 percentage) internal pure returns (uint256 basisPoints) {
        return percentage * 100;
    }

    /**
     * @notice Converts basis points to percentage
     * @param basisPoints Basis points value
     * @return percentage Equivalent percentage
     */
    function bpsToPercentage(uint256 basisPoints) internal pure returns (uint256 percentage) {
        return basisPoints / 100;
    }

    /**
     * @notice Validates fee rate doesn't exceed maximum
     * @param feeBps Fee rate in basis points
     * @param maxFeeBps Maximum allowed fee in basis points
     * @return isValid True if fee is valid
     */
    function validateFeeRate(uint256 feeBps, uint256 maxFeeBps) internal pure returns (bool isValid) {
        return feeBps <= maxFeeBps && feeBps <= BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates total of multiple fees
     * @param fees Array of fee amounts
     * @return totalFees Sum of all fees
     */
    function sumFees(uint256[] memory fees) internal pure returns (uint256 totalFees) {
        for (uint256 i = 0; i < fees.length; i++) {
            totalFees += fees[i];
        }
        return totalFees;
    }
}
