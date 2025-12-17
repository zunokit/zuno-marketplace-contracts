// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title AuctionTypes
 * @notice Data structures and enums for auction system
 * @dev Defines all types used across the auction ecosystem
 */

// ============================================================================
// ENUMS
// ============================================================================

/**
 * @notice Types of auctions supported
 */
enum AuctionType {
    ENGLISH,
    DUTCH,
    RESERVE
}

/**
 * @notice Status of an auction
 */
enum AuctionStatus {
    CREATED,
    ACTIVE,
    ENDED,
    CANCELLED,
    SETTLED
}

// ============================================================================
// STRUCTS
// ============================================================================

/**
 * @notice Core auction information
 */
struct Auction {
    bytes32 auctionId;
    address nftContract;
    uint256 tokenId;
    uint256 amount;
    address seller;
    AuctionType auctionType;
    AuctionStatus status;
    uint256 startTime;
    uint256 endTime;
    uint256 startPrice;
    uint256 reservePrice;
    address highestBidder;
    uint256 highestBid;
    uint256 totalBids;
    bool settled;
}

/**
 * @notice Bid information
 */
struct Bid {
    address bidder;
    uint256 amount;
    uint256 timestamp;
    bool refunded;
    uint256 previousBid;
}

/**
 * @notice Auction creation parameters
 */
struct AuctionCreationParams {
    address nftContract;
    uint256 tokenId;
    uint256 amount;
    uint256 startPrice;
    uint256 reservePrice;
    uint256 duration;
    AuctionType auctionType;
    address seller;
    uint256 bidIncrement;
    bool extendOnBid;
}

/**
 * @notice Time calculation for auctions
 */
struct TimeCalculation {
    uint256 currentTime;
    uint256 startTime;
    uint256 endTime;
    uint256 remainingTime;
    bool hasStarted;
    bool hasEnded;
    bool shouldExtend;
    uint256 extensionTime;
}

/**
 * @notice Bid validation parameters
 */
struct BidValidationParams {
    bytes32 auctionId;
    address bidder;
    uint256 bidAmount;
    uint256 currentHighestBid;
    uint256 minBidIncrement;
    bool isFirstBid;
}

/**
 * @notice Auction validation result
 */
struct AuctionValidationResult {
    bool isValid;
    string errorMessage;
    uint256 suggestedValue;
}

// ============================================================================
// CONSTANTS
// ============================================================================

// Default minimum bid increment (5% = 500 basis points)
uint256 constant DEFAULT_MIN_BID_INCREMENT = 500;
