// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IPaymentDistributor
 * @notice Common interface for payment distribution across the marketplace
 * @dev Defines standard functions for distributing payments to sellers, platform, and royalty receivers
 */
interface IPaymentDistributor {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Payment distribution parameters
     */
    struct PaymentParams {
        address seller;
        address royaltyReceiver;
        address platformWallet;
        uint256 totalAmount;
        uint256 sellerAmount;
        uint256 platformFee;
        uint256 royaltyAmount;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event PaymentDistributed(
        address indexed seller,
        address indexed buyer,
        uint256 totalAmount,
        uint256 sellerAmount,
        uint256 platformFee,
        uint256 royaltyAmount
    );

    event PaymentFailed(address indexed recipient, uint256 amount, string reason);

    // ============================================================================
    // CORE PAYMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Distributes payment to all parties
     * @param params Payment distribution parameters
     */
    function distributePayment(PaymentParams calldata params) external payable;

    /**
     * @notice Calculates payment distribution breakdown
     * @param totalAmount Total transaction amount
     * @param platformFeeBps Platform fee in basis points
     * @param royaltyBps Royalty in basis points
     * @return sellerAmount Amount seller receives
     * @return platformFee Platform fee amount
     * @return royaltyAmount Royalty amount
     */
    function calculateDistribution(uint256 totalAmount, uint256 platformFeeBps, uint256 royaltyBps)
        external
        pure
        returns (uint256 sellerAmount, uint256 platformFee, uint256 royaltyAmount);

    /**
     * @notice Validates payment distribution parameters
     * @param params Payment parameters to validate
     * @return isValid True if parameters are valid
     * @return errorMessage Error message if invalid
     */
    function validatePaymentParams(PaymentParams calldata params)
        external
        pure
        returns (bool isValid, string memory errorMessage);
}
