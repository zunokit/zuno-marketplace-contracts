// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IListing
 * @notice Common interface for all listing operations across the marketplace
 * @dev Defines standard functions that all listing managers should implement
 */
interface IListing {
    // ============================================================================
    // EVENTS
    // ============================================================================

    event ListingCreated(
        bytes32 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price
    );

    event ListingCancelled(bytes32 indexed listingId, address indexed seller);

    event ListingUpdated(bytes32 indexed listingId, uint256 newPrice);

    event ListingSold(
        bytes32 indexed listingId, address indexed seller, address indexed buyer, uint256 price, uint256 timestamp
    );

    // ============================================================================
    // CORE LISTING FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a new listing
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param price Listing price
     * @param duration Listing duration in seconds
     * @return listingId Unique identifier for the listing
     */
    function createListing(address nftContract, uint256 tokenId, uint256 price, uint256 duration)
        external
        returns (bytes32 listingId);

    /**
     * @notice Cancels an existing listing
     * @param listingId Unique identifier of the listing
     */
    function cancelListing(bytes32 listingId) external;

    /**
     * @notice Updates listing price
     * @param listingId Unique identifier of the listing
     * @param newPrice New listing price
     */
    function updateListing(bytes32 listingId, uint256 newPrice) external;

    /**
     * @notice Retrieves listing information
     * @param listingId Unique identifier of the listing
     * @return nftContract Address of the NFT contract
     * @return tokenId Token ID
     * @return seller Address of the seller
     * @return price Listing price
     * @return active Whether listing is active
     */
    function getListing(bytes32 listingId)
        external
        view
        returns (address nftContract, uint256 tokenId, address seller, uint256 price, bool active);

    /**
     * @notice Checks if a listing is active
     * @param listingId Unique identifier of the listing
     * @return True if listing is active
     */
    function isListingActive(bytes32 listingId) external view returns (bool);

    /**
     * @notice Gets all listings for a user
     * @param user Address of the user
     * @return Array of listing IDs
     */
    function getUserListings(address user) external view returns (bytes32[] memory);
}
