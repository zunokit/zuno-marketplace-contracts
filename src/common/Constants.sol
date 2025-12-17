// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title Constants
 * @notice Centralized constants for the marketplace
 * @dev Contains all magic numbers and common values used across contracts
 */
library Constants {
    // ============================================================================
    // FEE CONSTANTS
    // ============================================================================

    /// @notice Basis points denominator (100% = 10000 BPS)
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Maximum fee in basis points (10%)
    uint256 public constant MAX_FEE_BPS = 1000;

    /// @notice Default maker fee (2.5%)
    uint256 public constant DEFAULT_MAKER_FEE_BPS = 250;

    /// @notice Default taker fee (2.5%)
    uint256 public constant DEFAULT_TAKER_FEE_BPS = 250;

    /// @notice Maximum royalty fee (10%)
    uint256 public constant MAX_ROYALTY_BPS = 1000;

    // ============================================================================
    // AUCTION CONSTANTS
    // ============================================================================

    /// @notice Minimum auction duration (1 hour)
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;

    /// @notice Maximum auction duration (30 days)
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    /// @notice Default auction extension time (15 minutes)
    uint256 public constant DEFAULT_EXTENSION_TIME = 15 minutes;

    /// @notice Minimum bid increment (1%)
    uint256 public constant MIN_BID_INCREMENT_BPS = 100;

    /// @notice Time threshold for auction extension (15 minutes)
    uint256 public constant EXTENSION_THRESHOLD = 15 minutes;

    // ============================================================================
    // LISTING CONSTANTS
    // ============================================================================

    /// @notice Minimum listing duration (1 hour)
    uint256 public constant MIN_LISTING_DURATION = 1 hours;

    /// @notice Maximum listing duration (365 days)
    uint256 public constant MAX_LISTING_DURATION = 365 days;

    /// @notice Default listing duration (7 days)
    uint256 public constant DEFAULT_LISTING_DURATION = 7 days;

    // ============================================================================
    // OFFER CONSTANTS
    // ============================================================================

    /// @notice Minimum offer duration (1 hour)
    uint256 public constant MIN_OFFER_DURATION = 1 hours;

    /// @notice Maximum offer duration (30 days)
    uint256 public constant MAX_OFFER_DURATION = 30 days;

    /// @notice Default offer duration (24 hours)
    uint256 public constant DEFAULT_OFFER_DURATION = 24 hours;

    // ============================================================================
    // VALIDATION CONSTANTS
    // ============================================================================

    /// @notice Minimum price (0.001 ETH)
    uint256 public constant MIN_PRICE = 0.001 ether;

    /// @notice Maximum batch size for operations
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Maximum string length for names/descriptions
    uint256 public constant MAX_STRING_LENGTH = 256;

    // ============================================================================
    // STATUS CONSTANTS
    // ============================================================================

    /// @notice Listing status: Active
    uint256 public constant STATUS_ACTIVE = 1;

    /// @notice Listing status: Sold
    uint256 public constant STATUS_SOLD = 2;

    /// @notice Listing status: Cancelled
    uint256 public constant STATUS_CANCELLED = 3;

    /// @notice Listing status: Expired
    uint256 public constant STATUS_EXPIRED = 4;

    // ============================================================================
    // ERC INTERFACE IDS
    // ============================================================================

    /// @notice ERC721 interface ID (derived from type(IERC721).interfaceId)
    bytes4 public constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;

    /// @notice ERC1155 interface ID (derived from type(IERC1155).interfaceId)
    bytes4 public constant ERC1155_INTERFACE_ID = type(IERC1155).interfaceId;

    /// @notice ERC2981 (Royalty) interface ID (derived from type(IERC2981).interfaceId)
    bytes4 public constant ERC2981_INTERFACE_ID = type(IERC2981).interfaceId;

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Check if a fee is valid (not exceeding maximum)
     * @param feeBps Fee in basis points
     * @return valid True if fee is valid
     */
    function isValidFee(uint256 feeBps) internal pure returns (bool valid) {
        return feeBps <= MAX_FEE_BPS;
    }

    /**
     * @notice Check if a duration is valid for listings
     * @param duration Duration in seconds
     * @return valid True if duration is valid
     */
    function isValidListingDuration(uint256 duration) internal pure returns (bool valid) {
        return duration >= MIN_LISTING_DURATION && duration <= MAX_LISTING_DURATION;
    }

    /**
     * @notice Check if a duration is valid for auctions
     * @param duration Duration in seconds
     * @return valid True if duration is valid
     */
    function isValidAuctionDuration(uint256 duration) internal pure returns (bool valid) {
        return duration >= MIN_AUCTION_DURATION && duration <= MAX_AUCTION_DURATION;
    }

    /**
     * @notice Check if a price is valid (above minimum)
     * @param price Price in wei
     * @return valid True if price is valid
     */
    function isValidPrice(uint256 price) internal pure returns (bool valid) {
        return price >= MIN_PRICE;
    }

    /**
     * @notice Check if a duration is valid for offers
     * @param duration Duration in seconds
     * @return valid True if duration is valid
     */
    function isValidOfferDuration(uint256 duration) internal pure returns (bool valid) {
        return duration >= MIN_OFFER_DURATION && duration <= MAX_OFFER_DURATION;
    }

    /**
     * @notice Check if a batch size is valid
     * @param size Batch size
     * @return valid True if batch size is valid
     */
    function isValidBatchSize(uint256 size) internal pure returns (bool valid) {
        return size > 0 && size <= MAX_BATCH_SIZE;
    }
}
