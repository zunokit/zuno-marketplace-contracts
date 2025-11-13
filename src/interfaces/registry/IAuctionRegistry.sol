// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IAuctionRegistry
 * @notice Interface for managing auction contracts and factory
 * @dev Provides unified access to different auction types
 */
interface IAuctionRegistry {
    /**
     * @notice Auction types supported by the marketplace
     */
    enum AuctionType {
        ENGLISH, // Traditional ascending bid auction
        DUTCH, // Descending price auction
        SEALED_BID // Future: sealed bid auction
    }

    /**
     * @notice Emitted when an auction contract is registered
     * @param auctionType The auction type
     * @param auctionContract The auction contract address
     */
    event AuctionRegistered(AuctionType indexed auctionType, address indexed auctionContract);

    /**
     * @notice Emitted when auction factory is updated
     * @param oldFactory The old factory address
     * @param newFactory The new factory address
     */
    event AuctionFactoryUpdated(address oldFactory, address newFactory);

    /**
     * @notice Get the auction contract for a specific type
     * @param auctionType The auction type
     * @return The auction contract address
     */
    function getAuctionContract(AuctionType auctionType) external view returns (address);

    /**
     * @notice Get the auction factory contract
     * @return The auction factory contract address
     */
    function getAuctionFactory() external view returns (address);

    /**
     * @notice Register a new auction contract
     * @param auctionType The auction type
     * @param auctionContract The auction contract address
     */
    function registerAuction(AuctionType auctionType, address auctionContract) external;

    /**
     * @notice Update the auction factory contract
     * @param newFactory The new auction factory contract address
     */
    function updateAuctionFactory(address newFactory) external;

    /**
     * @notice Check if an address is a registered auction contract
     * @param auctionContract The address to check
     * @return True if the address is a registered auction contract
     */
    function isRegisteredAuction(address auctionContract) external view returns (bool);

    /**
     * @notice Get all registered auction contracts
     * @return types Array of auction types
     * @return contracts Array of auction contract addresses
     */
    function getAllAuctions() external view returns (AuctionType[] memory types, address[] memory contracts);
}
