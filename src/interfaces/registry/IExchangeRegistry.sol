// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IExchangeRegistry
 * @notice Interface for managing exchange contracts across different token standards
 * @dev Provides unified access to exchange contracts based on token type detection
 */
interface IExchangeRegistry {
    /**
     * @notice Token standards supported by the marketplace
     */
    enum TokenStandard {
        ERC721,
        ERC1155,
        ERC6551, // Future support for token-bound accounts
        ERC404 // Future support for semi-fungible tokens
    }

    /**
     * @notice Emitted when a new exchange is registered
     * @param standard The token standard
     * @param exchange The exchange contract address
     */
    event ExchangeRegistered(TokenStandard indexed standard, address indexed exchange);

    /**
     * @notice Emitted when an exchange is updated
     * @param standard The token standard
     * @param oldExchange The old exchange address
     * @param newExchange The new exchange address
     */
    event ExchangeUpdated(TokenStandard indexed standard, address oldExchange, address newExchange);

    /**
     * @notice Get the exchange contract for a specific token standard
     * @param standard The token standard
     * @return The exchange contract address
     */
    function getExchange(TokenStandard standard) external view returns (address);

    /**
     * @notice Get the appropriate exchange for a given NFT contract
     * @param nftContract The NFT contract address
     * @return The exchange contract address
     */
    function getExchangeForToken(address nftContract) external view returns (address);

    /**
     * @notice Get the exchange that manages a specific listing
     * @param listingId The listing identifier
     * @return The exchange contract address
     */
    function getExchangeForListing(bytes32 listingId) external view returns (address);

    /**
     * @notice Register a new exchange contract
     * @param standard The token standard
     * @param exchange The exchange contract address
     */
    function registerExchange(TokenStandard standard, address exchange) external;

    /**
     * @notice Update an existing exchange contract
     * @param standard The token standard
     * @param newExchange The new exchange contract address
     */
    function updateExchange(TokenStandard standard, address newExchange) external;

    /**
     * @notice Check if an address is a registered exchange
     * @param exchange The address to check
     * @return True if the address is a registered exchange
     */
    function isRegisteredExchange(address exchange) external view returns (bool);

    /**
     * @notice Get all registered exchanges
     * @return standards Array of token standards
     * @return exchanges Array of exchange addresses
     */
    function getAllExchanges() external view returns (TokenStandard[] memory standards, address[] memory exchanges);
}
