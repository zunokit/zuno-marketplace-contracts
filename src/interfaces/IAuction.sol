// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";

/**
 * @title IAuction
 * @notice Interface for auction contracts
 * @dev Defines the standard interface for all auction implementations
 */
interface IAuction {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct Auction {
        bytes32 auctionId; // Unique auction identifier
        address nftContract; // NFT contract address
        uint256 tokenId; // Token ID being auctioned
        uint256 amount; // Amount (for ERC1155, 1 for ERC721)
        address seller; // Seller address
        uint256 startPrice; // Starting price
        uint256 reservePrice; // Reserve price (minimum acceptable)
        uint256 startTime; // Auction start timestamp
        uint256 endTime; // Auction end timestamp
        AuctionStatus status; // Current auction status
        AuctionType auctionType; // Type of auction
        address highestBidder; // Current highest bidder (English only)
        uint256 highestBid; // Current highest bid (English only)
        uint256 bidCount; // Total number of bids
    }

    struct Bid {
        address bidder; // Bidder address
        uint256 amount; // Bid amount
        uint256 timestamp; // Bid timestamp
        bool refunded; // Whether bid has been refunded
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event AuctionCreated(
        bytes32 indexed auctionId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 startTime,
        uint256 endTime,
        uint8 auctionType
    );

    event AuctionCancelled(bytes32 indexed auctionId, address indexed seller, string reason);

    // Debug event for NFT validation troubleshooting
    event DebugNFTValidation(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed seller,
        bool isAvailable,
        uint8 status,
        uint256 timestamp
    );

    // ============================================================================
    // AUCTION MANAGEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a new auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @param auctionType Type of auction (English or Dutch)
     * @param seller Address of the seller (NFT owner)
     * @return auctionId Unique identifier for the created auction
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        AuctionType auctionType,
        address seller
    ) external returns (bytes32 auctionId);

    /**
     * @notice Cancels an active auction
     * @param auctionId Unique identifier of the auction to cancel
     */
    function cancelAuction(bytes32 auctionId) external;

    /**
     * @notice Settles a completed auction
     * @param auctionId Unique identifier of the auction to settle
     */
    function settleAuction(bytes32 auctionId) external;

    // ============================================================================
    // BIDDING FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction
     * @param auctionId Unique identifier of the auction
     */
    function placeBid(bytes32 auctionId) external payable;

    /**
     * @notice Purchases NFT in a Dutch auction
     * @param auctionId Unique identifier of the auction
     */
    function buyNow(bytes32 auctionId) external payable;

    /**
     * @notice Withdraws a refunded bid
     * @param auctionId Unique identifier of the auction
     */
    function withdrawBid(bytes32 auctionId) external;

    // ============================================================================
    // FACTORY FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the actual bidder
     */
    function placeBidFor(bytes32 auctionId, address bidder) external payable;

    /**
     * @notice Purchases NFT in a Dutch auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param buyer Address of the actual buyer
     */
    function buyNowFor(bytes32 auctionId, address buyer) external payable;

    /**
     * @notice Withdraws a refunded bid (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the actual bidder
     */
    function withdrawBidFor(bytes32 auctionId, address bidder) external;

    /**
     * @notice Cancels an auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param seller Address of the seller
     */
    function cancelAuctionFor(bytes32 auctionId, address seller) external;

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets auction details
     * @param auctionId Unique identifier of the auction
     * @return auction Auction struct with all details
     */
    function getAuction(bytes32 auctionId) external view returns (Auction memory auction);

    /**
     * @notice Gets current price for a Dutch auction
     * @param auctionId Unique identifier of the auction
     * @return currentPrice Current price of the Dutch auction
     */
    function getCurrentPrice(bytes32 auctionId) external view returns (uint256 currentPrice);

    /**
     * @notice Gets bid details for a specific bidder
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the bidder
     * @return bid Bid struct with details
     */
    function getBid(bytes32 auctionId, address bidder) external view returns (Bid memory bid);

    /**
     * @notice Gets all bids for an auction
     * @param auctionId Unique identifier of the auction
     * @return bids Array of all bids
     */
    function getAllBids(bytes32 auctionId) external view returns (Bid[] memory bids);

    /**
     * @notice Checks if an auction is active
     * @param auctionId Unique identifier of the auction
     * @return isActive Whether the auction is currently active
     */
    function isAuctionActive(bytes32 auctionId) external view returns (bool isActive);

    /**
     * @notice Gets auctions by seller
     * @param seller Address of the seller
     * @return auctionIds Array of auction IDs
     */
    function getAuctionsBySeller(address seller) external view returns (bytes32[] memory auctionIds);

    /**
     * @notice Gets auctions by NFT contract
     * @param nftContract Address of the NFT contract
     * @return auctionIds Array of auction IDs
     */
    function getAuctionsByContract(address nftContract) external view returns (bytes32[] memory auctionIds);

    /**
     * @notice Gets active auctions
     * @return auctionIds Array of active auction IDs
     */
    function getActiveAuctions() external view returns (bytes32[] memory auctionIds);

    /**
     * @notice Gets pending refund amount for a bidder
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the bidder
     * @return refundAmount Amount available for refund
     */
    function getPendingRefund(bytes32 auctionId, address bidder) external view returns (uint256 refundAmount);

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Pauses/unpauses the auction contract
     * @param paused Whether to pause or unpause
     */
    function setPaused(bool paused) external;

    /**
     * @notice Updates minimum auction duration
     * @param newMinDuration New minimum duration in seconds
     */
    function setMinAuctionDuration(uint256 newMinDuration) external;

    /**
     * @notice Updates maximum auction duration
     * @param newMaxDuration New maximum duration in seconds
     */
    function setMaxAuctionDuration(uint256 newMaxDuration) external;

    /**
     * @notice Updates minimum bid increment percentage
     * @param newIncrement New increment percentage (in basis points)
     */
    function setMinBidIncrement(uint256 newIncrement) external;
}
