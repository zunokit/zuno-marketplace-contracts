// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICollectionRegistry} from "src/interfaces/registry/ICollectionRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CollectionRegistry
 * @notice Central registry for managing collection factories
 * @dev Provides unified access to collection creation across different token standards
 */
contract CollectionRegistry is ICollectionRegistry, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Mapping from token type string (e.g., "ERC721", "ERC1155") to factory address
    mapping(string => address) private s_factories;

    // Mapping to check if address is a registered factory
    mapping(address => bool) private s_isFactory;

    // Mapping from collection address to token type
    mapping(address => string) private s_collectionToTokenType;

    // Mapping to verify collections were created by registered factories
    mapping(address => bool) private s_isVerifiedCollection;

    // Array to track all token types
    string[] private s_tokenTypes;

    error CollectionRegistry__ZeroAddress();
    error CollectionRegistry__FactoryAlreadyRegistered();
    error CollectionRegistry__FactoryNotRegistered();
    error CollectionRegistry__InvalidTokenType();
    error CollectionRegistry__CollectionNotVerified();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function getFactory(string memory tokenType) external view override returns (address) {
        address factory = s_factories[tokenType];
        if (factory == address(0)) revert CollectionRegistry__FactoryNotRegistered();
        return factory;
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function registerFactory(string memory tokenType, address factory) external override onlyRole(ADMIN_ROLE) {
        if (factory == address(0)) revert CollectionRegistry__ZeroAddress();
        if (bytes(tokenType).length == 0) revert CollectionRegistry__InvalidTokenType();
        if (s_factories[tokenType] != address(0)) revert CollectionRegistry__FactoryAlreadyRegistered();

        s_factories[tokenType] = factory;
        s_isFactory[factory] = true;
        s_tokenTypes.push(tokenType);

        emit FactoryRegistered(tokenType, factory);
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function updateFactory(string memory tokenType, address newFactory) external override onlyRole(ADMIN_ROLE) {
        if (newFactory == address(0)) revert CollectionRegistry__ZeroAddress();

        address oldFactory = s_factories[tokenType];
        if (oldFactory == address(0)) revert CollectionRegistry__FactoryNotRegistered();

        s_isFactory[oldFactory] = false;
        s_factories[tokenType] = newFactory;
        s_isFactory[newFactory] = true;

        emit FactoryUpdated(tokenType, oldFactory, newFactory);
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function verifyCollection(address collection)
        external
        view
        override
        returns (bool isValid, string memory tokenType)
    {
        if (collection == address(0)) {
            revert CollectionRegistry__ZeroAddress();
        }

        isValid = s_isVerifiedCollection[collection];
        tokenType = s_collectionToTokenType[collection];

        return (isValid, tokenType);
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function isRegisteredFactory(address factory) external view override returns (bool) {
        return s_isFactory[factory];
    }

    /**
     * @inheritdoc ICollectionRegistry
     */
    function getAllFactories() external view override returns (string[] memory tokenTypes, address[] memory factories) {
        uint256 length = s_tokenTypes.length;
        tokenTypes = new string[](length);
        factories = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            tokenTypes[i] = s_tokenTypes[i];
            factories[i] = s_factories[s_tokenTypes[i]];
        }

        return (tokenTypes, factories);
    }

    /**
     * @notice Register a collection as verified
     * @dev Called by factory contracts when a collection is created
     * @param collection The collection address
     * @param tokenType The token type
     */
    function registerCollection(address collection, string memory tokenType) external {
        if (!s_isFactory[msg.sender]) revert CollectionRegistry__FactoryNotRegistered();
        if (collection == address(0)) revert CollectionRegistry__ZeroAddress();

        s_isVerifiedCollection[collection] = true;
        s_collectionToTokenType[collection] = tokenType;

        emit CollectionVerified(collection, tokenType);
    }

    /**
     * @notice Check if a collection is verified
     * @param collection The collection address to check
     * @return True if the collection is verified
     */
    function isVerifiedCollection(address collection) external view returns (bool) {
        return s_isVerifiedCollection[collection];
    }
}
