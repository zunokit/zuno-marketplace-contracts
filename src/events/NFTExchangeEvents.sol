// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title NFTExchangeEvents
 * @notice Core marketplace events for listings and sales
 * @dev Simple event definitions for basic marketplace operations
 * @dev For detailed auction events, see AuctionEvents.sol
 * @dev For collection events, see CollectionEvents.sol
 */

// ============================================================================
// LISTING EVENTS
// ============================================================================

/**
 * @notice Emitted when an NFT is listed for sale
 * @param listingId Unique identifier for the listing
 * @param contractAddress NFT contract address
 * @param tokenId Token ID being listed
 * @param seller Address of the seller
 * @param price Listing price
 */
event NFTListed(
    bytes32 indexed listingId, address indexed contractAddress, uint256 indexed tokenId, address seller, uint256 price
);

/**
 * @notice Emitted when an NFT is sold
 * @param listingId Unique identifier for the listing
 * @param contractAddress NFT contract address
 * @param tokenId Token ID that was sold
 * @param seller Address of the seller
 * @param buyer Address of the buyer
 * @param price Sale price
 */
event NFTSold(
    bytes32 indexed listingId,
    address indexed contractAddress,
    uint256 indexed tokenId,
    address seller,
    address buyer,
    uint256 price
);

/**
 * @notice Emitted when a listing is cancelled
 * @param listingId Unique identifier for the listing
 * @param contractAddress NFT contract address
 * @param tokenId Token ID that was delisted
 * @param seller Address of the seller
 */
event ListingCancelled(
    bytes32 indexed listingId, address indexed contractAddress, uint256 indexed tokenId, address seller
);

/**
 * @notice Emitted when payment is distributed after a sale
 * @param listingId Unique identifier for the listing
 * @param seller Address of the seller
 * @param buyer Address of the buyer
 * @param totalPrice Total price paid by buyer
 * @param sellerAmount Net amount received by seller
 * @param marketplaceFee Marketplace fee amount
 * @param royaltyAmount Royalty fee amount
 * @param royaltyRecipient Address receiving royalty (address(0) if no royalty)
 */
event PaymentDistributed(
    bytes32 indexed listingId,
    address indexed seller,
    address indexed buyer,
    uint256 totalPrice,
    uint256 sellerAmount,
    uint256 marketplaceFee,
    uint256 royaltyAmount,
    address royaltyRecipient
);

/**
 * @notice Emitted when a listing price is updated
 * @param listingId Unique identifier for the listing
 * @param seller Address of the seller
 * @param oldPrice Previous listing price
 * @param newPrice New listing price
 * @param timestamp When the update occurred
 */
event ListingPriceUpdated(
    bytes32 indexed listingId,
    address indexed seller,
    uint256 oldPrice,
    uint256 newPrice,
    uint256 timestamp
);

// ============================================================================
// MARKETPLACE CONFIGURATION EVENTS
// ============================================================================

/**
 * @notice Emitted when marketplace wallet address is updated
 * @param oldWallet Previous wallet address
 * @param newWallet New wallet address
 */
event MarketplaceWalletUpdated(address indexed oldWallet, address indexed newWallet);

/**
 * @notice Emitted when taker fee is updated
 * @param oldFee Previous fee amount
 * @param newFee New fee amount
 */
event TakerFeeUpdated(uint256 oldFee, uint256 newFee);

// ============================================================================
// COLLECTION VERIFICATION EVENTS
// ============================================================================

/**
 * @notice Emitted when a collection is verified
 * @param collectionAddress Address of the verified collection
 */
event CollectionVerified(address indexed collectionAddress);

/**
 * @notice Emitted when a collection verification is removed
 * @param collectionAddress Address of the unverified collection
 */
event CollectionUnverified(address indexed collectionAddress);

// ============================================================================
// LISTING EXPIRATION EVENTS
// ============================================================================

/**
 * @notice Emitted when a listing is marked as expired
 * @param listingId Unique identifier for the listing
 * @param contractAddress NFT contract address
 * @param tokenId Token ID that expired
 * @param seller Address of the seller
 * @param expiredAt Timestamp when listing expired
 */
event ListingExpired(
    bytes32 indexed listingId,
    address indexed contractAddress,
    uint256 indexed tokenId,
    address seller,
    uint256 expiredAt
);

// ============================================================================
// NOTE: Auction and Collection Creation Events
// ============================================================================
// For comprehensive auction events, use AuctionEvents.sol
// For collection creation events, use CollectionEvents.sol
// These dedicated event files provide more detailed event structures
