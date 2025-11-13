// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFeeCalculator
 * @notice Common interface for fee calculations across the marketplace
 * @dev Defines standard functions for calculating various types of fees
 */
interface IFeeCalculator {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Fee breakdown structure
     */
    struct FeeBreakdown {
        uint256 platformFee;
        uint256 royaltyFee;
        uint256 takerFee;
        uint256 totalFees;
        uint256 netAmount;
    }

    /**
     * @notice Fee configuration
     */
    struct FeeConfig {
        uint256 platformFeeBps; // Platform fee in basis points
        uint256 takerFeeBps; // Taker fee in basis points
        uint256 royaltyBps; // Royalty in basis points
        uint256 maxFeeBps; // Maximum allowed fee
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event FeeCalculated(
        address indexed user,
        uint256 amount,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 takerFee,
        uint256 totalFees
    );

    event FeeConfigUpdated(uint256 platformFeeBps, uint256 takerFeeBps, uint256 maxFeeBps);

    // ============================================================================
    // CORE FEE CALCULATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Calculates complete fee breakdown for a transaction
     * @param amount Transaction amount
     * @param config Fee configuration
     * @return breakdown Complete fee breakdown
     */
    function calculateFees(uint256 amount, FeeConfig calldata config)
        external
        pure
        returns (FeeBreakdown memory breakdown);

    /**
     * @notice Calculates platform fee
     * @param amount Transaction amount
     * @param platformFeeBps Platform fee in basis points
     * @return platformFee Calculated platform fee
     */
    function calculatePlatformFee(uint256 amount, uint256 platformFeeBps) external pure returns (uint256 platformFee);

    /**
     * @notice Calculates taker fee (buyer-side fee)
     * @param amount Transaction amount
     * @param takerFeeBps Taker fee in basis points
     * @return takerFee Calculated taker fee
     */
    function calculateTakerFee(uint256 amount, uint256 takerFeeBps) external pure returns (uint256 takerFee);

    /**
     * @notice Calculates royalty fee
     * @param amount Transaction amount
     * @param royaltyBps Royalty in basis points
     * @return royaltyFee Calculated royalty fee
     */
    function calculateRoyaltyFee(uint256 amount, uint256 royaltyBps) external pure returns (uint256 royaltyFee);

    /**
     * @notice Calculates total price buyer needs to pay (base price + fees)
     * @param basePrice Base item price
     * @param config Fee configuration
     * @return totalPrice Total price including all fees
     */
    function calculateBuyerPrice(uint256 basePrice, FeeConfig calldata config)
        external
        pure
        returns (uint256 totalPrice);

    /**
     * @notice Calculates net amount seller receives (after fees)
     * @param salePrice Sale price
     * @param config Fee configuration
     * @return netAmount Net amount seller receives
     */
    function calculateSellerNet(uint256 salePrice, FeeConfig calldata config) external pure returns (uint256 netAmount);

    /**
     * @notice Validates fee configuration
     * @param config Fee configuration to validate
     * @return isValid True if configuration is valid
     * @return errorMessage Error message if invalid
     */
    function validateFeeConfig(FeeConfig calldata config)
        external
        pure
        returns (bool isValid, string memory errorMessage);

    /**
     * @notice Gets current fee configuration
     * @return config Current fee configuration
     */
    function getFeeConfig() external view returns (FeeConfig memory config);
}
