// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMarketplaceValidator
 * @notice Interface for cross-validation between auction and marketplace systems
 * @dev This interface allows auction contracts to check if NFTs are already listed
 *      and marketplace contracts to check if NFTs are already in auction
 */
interface IMarketplaceValidator {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Status of an NFT in the marketplace ecosystem
     */
    enum NFTStatus {
        AVAILABLE, // NFT is available for listing/auction
        LISTED, // NFT is listed for sale
        IN_AUCTION, // NFT is in auction
        SOLD, // NFT has been sold
        CANCELLED // Listing/auction was cancelled
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event NFTStatusChanged(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed owner,
        NFTStatus oldStatus,
        NFTStatus newStatus
    );

    event ExchangeRegistered(address indexed exchangeAddress, uint8 indexed exchangeType);

    event AuctionRegistered(address indexed auctionAddress, uint8 indexed auctionType);

    event EmergencyManagerSet(address indexed emergencyManager);

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Checks if an NFT is available for listing or auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to check
     * @param owner Owner of the NFT
     * @return isAvailable Whether the NFT is available
     * @return currentStatus Current status of the NFT
     */
    function isNFTAvailable(address nftContract, uint256 tokenId, address owner)
        external
        view
        returns (bool isAvailable, NFTStatus currentStatus);

    /**
     * @notice Checks if an NFT is currently listed for sale
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to check
     * @param owner Owner of the NFT
     * @return isListed Whether the NFT is listed
     */
    function isNFTListed(address nftContract, uint256 tokenId, address owner) external view returns (bool isListed);

    /**
     * @notice Checks if an NFT is currently in auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to check
     * @param owner Owner of the NFT
     * @return inAuction Whether the NFT is in auction
     */
    function isNFTInAuction(address nftContract, uint256 tokenId, address owner) external view returns (bool inAuction);

    /**
     * @notice Gets the current status of an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to check
     * @param owner Owner of the NFT
     * @return status Current status of the NFT
     */
    function getNFTStatus(address nftContract, uint256 tokenId, address owner) external view returns (NFTStatus status);

    // ============================================================================
    // STATE MANAGEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Updates NFT status when listed for sale
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param owner Owner of the NFT
     * @param listingId Unique listing identifier
     */
    function setNFTListed(address nftContract, uint256 tokenId, address owner, bytes32 listingId) external;

    /**
     * @notice Updates NFT status when put in auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param owner Owner of the NFT
     * @param auctionId Unique auction identifier
     */
    function setNFTInAuction(address nftContract, uint256 tokenId, address owner, bytes32 auctionId) external;

    /**
     * @notice Updates NFT status when listing/auction is cancelled
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param owner Owner of the NFT
     */
    function setNFTAvailable(address nftContract, uint256 tokenId, address owner) external;

    /**
     * @notice Updates NFT status when sold
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param oldOwner Previous owner of the NFT
     * @param newOwner New owner of the NFT
     */
    function setNFTSold(address nftContract, uint256 tokenId, address oldOwner, address newOwner) external;

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Registers an exchange contract
     * @param exchangeAddress Address of the exchange contract
     * @param exchangeType Type of exchange (0 = ERC721, 1 = ERC1155)
     */
    function registerExchange(address exchangeAddress, uint8 exchangeType) external;

    /**
     * @notice Registers an auction contract
     * @param auctionAddress Address of the auction contract
     * @param auctionType Type of auction (0 = English, 1 = Dutch)
     */
    function registerAuction(address auctionAddress, uint8 auctionType) external;

    /**
     * @notice Checks if an address is a registered exchange
     * @param exchangeAddress Address to check
     * @return isRegistered Whether the address is a registered exchange
     */
    function isRegisteredExchange(address exchangeAddress) external view returns (bool isRegistered);

    /**
     * @notice Checks if an address is a registered auction
     * @param auctionAddress Address to check
     * @return isRegistered Whether the address is a registered auction
     */
    function isRegisteredAuction(address auctionAddress) external view returns (bool isRegistered);

    /**
     * @notice Emergency function to reset NFT status (admin only)
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param owner Owner of the NFT
     */
    function emergencyResetNFTStatus(address nftContract, uint256 tokenId, address owner) external;
}
