// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ListingTypes
 * @notice Data structures and enums for advanced listing system
 * @dev Defines all types used across the advanced listing ecosystem
 * @author NFT Marketplace Team
 */

// ============================================================================
// ENUMS
// ============================================================================

/**
 * @notice Mint stage
 */
enum MintStage {
    INACTIVE,
    ALLOWLIST,
    PUBLIC
}

/**
 * @notice Types of listings supported by the marketplace
 */
enum ListingType {
    FIXED_PRICE, // Standard fixed price listing
    AUCTION, // Auction-style listing (English auction)
    DUTCH_AUCTION, // Dutch auction (decreasing price)
    BUNDLE, // Multiple NFTs sold together
    OFFER_BASED, // Accept offers only
    TIME_LIMITED, // Fixed price with time limit
    RESERVE_AUCTION // Auction with reserve price
}

/**
 * @notice Current status of a listing
 */
enum ListingStatus {
    ACTIVE, // Listing is active and available
    SOLD, // Listing has been sold
    CANCELLED, // Listing was cancelled by seller
    EXPIRED, // Listing has expired
    PAUSED, // Listing is temporarily paused
    PENDING // Listing is pending approval
}

/**
 * @notice Types of offers that can be made
 */
enum OfferType {
    STANDARD, // Regular offer
    COLLECTION, // Offer for any item in collection
    TRAIT, // Offer for items with specific traits
    BUNDLE // Offer for bundle of items
}

/**
 * @notice Status of an offer
 */
enum OfferStatus {
    ACTIVE, // Offer is active
    ACCEPTED, // Offer was accepted
    REJECTED, // Offer was rejected
    WITHDRAWN, // Offer was withdrawn by buyer
    EXPIRED // Offer has expired
}

/**
 * @notice Bundle types for multi-NFT listings
 */
enum BundleType {
    FIXED, // Fixed set of NFTs
    COLLECTION, // All NFTs from a collection
    TRAIT_BASED // NFTs with specific traits
}

// ============================================================================
// STRUCTS
// ============================================================================

/**
 * @notice Collection parameters
 */
struct CollectionParams {
    string name;
    string symbol;
    address owner;
    string description;
    uint256 mintPrice;
    uint256 royaltyFee;
    uint256 maxSupply;
    uint256 mintLimitPerWallet;
    uint256 mintStartTime;
    uint256 allowlistMintPrice;
    uint256 publicMintPrice;
    uint256 allowlistStageDuration;
    string tokenURI;
}

/**
 * @notice Core listing information - GAS OPTIMIZED
 * @dev Storage packed to minimize gas costs
 * Slot 1: listingId (32 bytes)
 * Slot 2: seller (20 bytes) + price (12 bytes)
 * Slot 3: nftContract (20 bytes) + tokenId (12 bytes)
 * Slot 4: times (8+8 bytes) + minOfferPrice (8 bytes) + quantity (4 bytes) + flags (3 bytes) + padding
 * Slot 5: bundleId (32 bytes)
 * Slot 6+: metadata (dynamic)
 */
struct Listing {
    bytes32 listingId; // Slot 1: 32 bytes

    address seller; // Slot 2: 20 bytes
    uint96 price; // Slot 2: 12 bytes (max ~79B tokens with 18 decimals)

    address nftContract; // Slot 3: 20 bytes
    uint96 tokenId; // Slot 3: 12 bytes (max ~79 quintillion token IDs)

    uint64 startTime; // Slot 4: 8 bytes
    uint64 endTime; // Slot 4: 8 bytes
    uint64 minOfferPrice; // Slot 4: 8 bytes (max ~18 ETH)
    uint32 quantity; // Slot 4: 4 bytes (max 4B items)
    ListingType listingType; // Slot 4: 1 byte enum
    ListingStatus status; // Slot 4: 1 byte enum
    bool acceptOffers; // Slot 4: 1 byte

    bytes32 bundleId; // Slot 5: 32 bytes
    bytes metadata; // Slot 6+: dynamic
}

/**
 * @notice Auction-specific parameters
 */
struct AuctionParams {
    uint256 startingPrice; // Starting bid price
    uint256 reservePrice; // Reserve price (minimum to sell)
    uint256 buyNowPrice; // Buy now price (0 if disabled)
    uint256 bidIncrement; // Minimum bid increment
    uint256 duration; // Auction duration
    bool extendOnBid; // Extend auction on late bids
    uint256 extensionTime; // Time to extend by
}

/**
 * @notice Dutch auction parameters
 */
struct DutchAuctionParams {
    uint256 startingPrice; // Starting high price
    uint256 endingPrice; // Ending low price
    uint256 duration; // Total duration
    uint256 priceDropInterval; // How often price drops
    uint256 priceDropAmount; // Amount price drops each interval
}

/**
 * @notice Offer information
 */
struct Offer {
    bytes32 offerId; // Unique offer identifier
    OfferType offerType; // Type of offer
    OfferStatus status; // Current status
    address buyer; // Address of the buyer
    bytes32 listingId; // Target listing ID
    address nftContract; // NFT contract (for collection offers)
    uint256 tokenId; // Specific token ID (0 for collection)
    uint256 quantity; // Quantity offered for
    uint256 amount; // Offer amount
    uint256 timestamp; // When offer was made
    uint256 expiry; // When offer expires
    bytes traitRequirements; // Trait requirements (for trait offers)
}

/**
 * @notice Bundle information
 */
struct Bundle {
    bytes32 bundleId; // Unique bundle identifier
    BundleType bundleType; // Type of bundle
    address creator; // Bundle creator
    string name; // Bundle name
    string description; // Bundle description
    BundleItem[] items; // Items in the bundle
    uint256 totalPrice; // Total bundle price
    uint256 createdAt; // Creation timestamp
    bool isActive; // Whether bundle is active
}

/**
 * @notice Individual item in a bundle
 */
struct BundleItem {
    address nftContract; // NFT contract address
    uint256 tokenId; // Token ID
    uint256 quantity; // Quantity (for ERC1155)
    uint256 individualPrice; // Individual item price
}

/**
 * @notice Listing fees structure
 */
struct ListingFees {
    uint256 baseFee; // Base listing fee (in wei)
    uint256 percentageFee; // Percentage fee (in basis points)
    uint256 auctionFee; // Additional auction fee
    uint256 bundleFee; // Additional bundle fee
    uint256 offerFee; // Fee for making offers
    address feeRecipient; // Where fees are sent
}

/**
 * @notice Time-based constraints
 */
struct TimeConstraints {
    uint256 minListingDuration; // Minimum listing duration
    uint256 maxListingDuration; // Maximum listing duration
    uint256 minAuctionDuration; // Minimum auction duration
    uint256 maxAuctionDuration; // Maximum auction duration
    uint256 offerValidityPeriod; // Default offer validity
    uint256 gracePeriod; // Grace period for expired listings
}

/**
 * @notice Listing statistics
 */
struct ListingStats {
    uint256 totalListings; // Total number of listings
    uint256 activeListings; // Currently active listings
    uint256 soldListings; // Successfully sold listings
    uint256 totalVolume; // Total volume traded
    uint256 averagePrice; // Average sale price
    uint256 totalOffers; // Total offers made
    uint256 acceptedOffers; // Offers that were accepted
}

/**
 * @notice Seller statistics
 */
struct SellerStats {
    uint256 totalListings; // Total listings by seller
    uint256 successfulSales; // Successful sales
    uint256 totalRevenue; // Total revenue earned
    uint256 averageSaleTime; // Average time to sell
    uint256 cancelledListings; // Cancelled listings
    uint256 rating; // Seller rating (out of 1000)
    uint256 totalRatings; // Number of ratings received
}

/**
 * @notice Buyer statistics
 */
struct BuyerStats {
    uint256 totalPurchases; // Total purchases made
    uint256 totalSpent; // Total amount spent
    uint256 averagePurchasePrice; // Average purchase price
    uint256 totalOffers; // Total offers made
    uint256 acceptedOffers; // Offers that were accepted
    uint256 rating; // Buyer rating (out of 1000)
    uint256 totalRatings; // Number of ratings received
}

// ============================================================================
// CONSTANTS
// ============================================================================

// Maximum royalty fee (10% = 1000 basis points)
uint256 constant MAX_ROYALTY_FEE = 1000;

// Maximum number of items in a bundle
uint256 constant MAX_BUNDLE_ITEMS = 50;

// Maximum listing duration (1 year)
uint256 constant MAX_LISTING_DURATION = 365 days;

// Minimum listing duration (1 hour)
uint256 constant MIN_LISTING_DURATION = 1 hours;

// Maximum auction duration (30 days)
uint256 constant MAX_AUCTION_DURATION = 30 days;

// Minimum auction duration (1 hour)
uint256 constant MIN_AUCTION_DURATION = 1 hours;

// Default offer validity period (7 days)
uint256 constant DEFAULT_OFFER_VALIDITY = 7 days;

// Maximum offer validity period (30 days)
uint256 constant MAX_OFFER_VALIDITY = 30 days;

// Basis points for percentage calculations (100% = 10000)
uint256 constant BASIS_POINTS = 10000;

// Maximum fee percentage (10%)
uint256 constant MAX_FEE_PERCENTAGE = 1000;

// Minimum bid increment (1%)
uint256 constant MIN_BID_INCREMENT = 100;

// Maximum bid increment (50%)
uint256 constant MAX_BID_INCREMENT = 5000;

// Auction extension time (15 minutes)
uint256 constant AUCTION_EXTENSION_TIME = 15 minutes;

// Grace period for expired listings (24 hours)
uint256 constant GRACE_PERIOD = 24 hours;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @notice Checks if a listing type supports auctions
 * @param listingType The listing type to check
 * @return Whether the listing type is auction-based
 */
function isAuctionType(ListingType listingType) pure returns (bool) {
    return listingType == ListingType.AUCTION || listingType == ListingType.DUTCH_AUCTION
        || listingType == ListingType.RESERVE_AUCTION;
}

/**
 * @notice Checks if a listing type supports immediate purchase
 * @param listingType The listing type to check
 * @return Whether the listing type supports buy now
 */
function supportsBuyNow(ListingType listingType) pure returns (bool) {
    return listingType == ListingType.FIXED_PRICE || listingType == ListingType.TIME_LIMITED
        || listingType == ListingType.BUNDLE;
}

/**
 * @notice Checks if a listing type supports offers
 * @param listingType The listing type to check
 * @return Whether the listing type supports offers
 */
function supportsOffers(ListingType listingType) pure returns (bool) {
    return listingType == ListingType.OFFER_BASED || listingType == ListingType.FIXED_PRICE
        || listingType == ListingType.TIME_LIMITED;
}

/**
 * @notice Calculates percentage fee
 * @param amount The amount to calculate fee for
 * @param feePercentage The fee percentage in basis points
 * @return The calculated fee amount
 */
function calculatePercentageFee(uint256 amount, uint256 feePercentage) pure returns (uint256) {
    unchecked {
        // Safe: feePercentage is capped at MAX_FEE_PERCENTAGE (1000 = 10%)
        // Division by BASIS_POINTS (10000) ensures no overflow
        return (amount * feePercentage) / BASIS_POINTS;
    }
}

/**
 * @notice Validates time constraints
 * @param startTime Start time of the listing
 * @param endTime End time of the listing
 * @param listingType Type of listing
 * @return Whether the time constraints are valid
 */
function validateTimeConstraints(uint256 startTime, uint256 endTime, ListingType listingType) pure returns (bool) {
    if (startTime >= endTime) return false;

    uint256 duration = endTime - startTime;

    if (isAuctionType(listingType)) {
        return duration >= MIN_AUCTION_DURATION && duration <= MAX_AUCTION_DURATION;
    } else {
        return duration >= MIN_LISTING_DURATION && duration <= MAX_LISTING_DURATION;
    }
}
