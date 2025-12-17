// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title FeeTypes
 * @notice Data structures for fee management
 * @dev Defines all fee-related types
 */

// ============================================================================
// STRUCTS
// ============================================================================

/**
 * @notice Fee breakdown for transparency
 */
struct FeeBreakdown {
    uint256 platformFee;
    uint256 royaltyAmount;
    address royaltyRecipient;
    uint256 netSellerAmount;
    uint256 totalBuyerCost;
}

/**
 * @notice Base fee configuration
 */
struct FeeConfig {
    uint256 makerFee; // Fee paid by seller (basis points)
    uint256 takerFee; // Fee paid by buyer (basis points)
    uint256 listingFee; // Fixed fee for creating listings (wei)
    uint256 auctionFee; // Additional fee for auctions (basis points)
    uint256 bundleFee; // Additional fee for bundle sales (basis points)
    bool isActive; // Whether fees are active
}

/**
 * @notice Fee tier configuration for volume discounts
 */
struct FeeTierConfig {
    uint256 volumeThreshold; // Minimum volume to reach this tier (wei)
    uint256 discountBps; // Discount in basis points
    string tierName; // Human-readable tier name
    bool isActive; // Whether this tier is active
}

/**
 * @notice User's current fee tier
 */
struct FeeTier {
    uint256 tierId; // Current tier ID
    uint256 discountBps; // Current discount in basis points
    uint256 lastUpdated; // Last time tier was updated
}

/**
 * @notice Collection-specific fee override
 */
struct CollectionFeeOverride {
    uint256 makerFeeOverride; // Override maker fee (basis points)
    uint256 takerFeeOverride; // Override taker fee (basis points)
    uint256 discountBps; // Additional discount for this collection
    bool hasOverride; // Whether override is active
    bool isVerified; // Whether collection is verified (for discounts)
    uint256 setAt; // When override was set
}

/**
 * @notice User volume tracking data
 */
struct UserVolumeData {
    uint256 totalVolume; // Total trading volume (wei)
    uint256 last30DaysVolume; // Volume in last 30 days (wei)
    uint256 lastTradeTimestamp; // Last trade timestamp
    uint256 tradeCount; // Total number of trades
}

/**
 * @notice VIP status configuration
 */
struct VIPStatus {
    bool isVIP; // Whether user has VIP status
    uint256 vipDiscountBps; // VIP-specific discount (basis points)
    uint256 vipExpiryTimestamp; // When VIP status expires
    string vipTier; // VIP tier name
}

/**
 * @notice Royalty information
 */
struct RoyaltyInfo {
    address receiver;
    uint256 amount;
    uint256 percentage;
    bool isValid;
    string source; // "ERC2981", "Collection", "Custom"
}

/**
 * @notice Royalty calculation parameters
 */
struct RoyaltyParams {
    address contractAddress;
    uint256 tokenId;
    uint256 salePrice;
    address feeContract;
}

/**
 * @notice Advanced royalty configuration
 */
struct AdvancedRoyaltyInfo {
    address primaryRecipient;
    uint256 primaryPercentage;
    address[] additionalRecipients;
    uint256[] additionalPercentages;
    uint256 totalPercentage;
    bool isActive;
    uint256 lastUpdated;
}

/**
 * @notice Royalty recipient info
 */
struct RoyaltyRecipient {
    address recipient;
    uint256 percentage;
    bool isActive;
    string name;
}

/**
 * @notice Royalty caps and limits
 */
struct RoyaltyCaps {
    uint256 maxPercentage;
    uint256 minAmount;
    uint256 maxAmount;
    bool enforced;
}

/**
 * @notice Payment distribution data
 */
struct PaymentData {
    address seller;
    address buyer;
    uint256 salePrice;
    uint256 marketplaceFee;
    uint256 royaltyAmount;
    address royaltyReceiver;
    address marketplaceWallet;
    uint256 netSellerAmount;
}

/**
 * @notice Fee calculation parameters
 */
struct FeeParams {
    uint256 price;
    uint256 takerFeeBps;
    uint256 royaltyAmount;
}
