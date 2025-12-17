// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CollectionParams} from "src/types/ListingTypes.sol";
import {ERC1155CollectionCreated, ERC1155CollectionCreatedWithAllowlist} from "src/events/CollectionEvents.sol";
import {ICollectionFactory} from "src/interfaces/IMarketplaceCore.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {ERC1155CollectionImplementation} from "src/core/proxy/ERC1155CollectionImplementation.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title ERC1155CollectionFactory
 * @notice Factory contract for creating ERC1155 collections only
 * @dev Split from original CollectionFactory to reduce contract size
 */
contract ERC1155CollectionFactory is ERC165, ICollectionFactory {
    // Implementation contract for minimal proxies
    address public immutable erc1155CollectionImplementation;

    // Track created collections
    mapping(address => bool) private s_validCollections;
    uint256 private s_totalCollections;

    // Events
    event ImplementationDeployed(address indexed implementation);

    /**
     * @notice Constructor deploys the implementation contract
     */
    constructor() {
        erc1155CollectionImplementation = address(new ERC1155CollectionImplementation());
        emit ImplementationDeployed(erc1155CollectionImplementation);
    }

    /**
     * @notice Creates a new ERC1155 collection using proxy pattern
     * @param params Collection parameters
     * @return The address of the created collection
     */
    function createERC1155Collection(CollectionParams memory params) external returns (address) {
        return _createCollectionInternal(params);
    }

    /**
     * @notice Creates a new ERC1155 collection with allowlist setup in a single transaction
     * @param params Collection parameters
     * @param allowlistAddresses Array of addresses to add to allowlist
     * @param enableAllowlistOnly If true, only allowlisted addresses can ever mint
     * @return The address of the created collection
     * @dev This reduces MetaMask confirmations from 3 to 1 when creating a collection with allowlist
     */
    function createCollectionWithAllowlist(
        CollectionParams memory params,
        address[] calldata allowlistAddresses,
        bool enableAllowlistOnly
    ) external returns (address) {
        // Create collection
        address collectionAddr = _createCollectionInternal(params);

        // Setup allowlist if addresses provided or mode needs to be set
        if (allowlistAddresses.length > 0 || enableAllowlistOnly) {
            BaseCollection(collectionAddr).setupAllowlist(allowlistAddresses, enableAllowlistOnly);
        }

        emit ERC1155CollectionCreatedWithAllowlist(
            collectionAddr, msg.sender, allowlistAddresses.length, enableAllowlistOnly
        );

        return collectionAddr;
    }

    /**
     * @notice Internal function to create collection with proxy
     * @param params Collection parameters
     * @return collectionAddr Address of created collection
     */
    function _createCollectionInternal(CollectionParams memory params) internal returns (address collectionAddr) {
        // Validate parameters
        _validateCollectionParams(params);

        // Deploy proxy
        collectionAddr = _deployCollectionProxy();

        // Initialize proxy
        _initializeCollection(collectionAddr, params);

        // Register collection
        _registerCollection(collectionAddr);

        return collectionAddr;
    }

    /**
     * @notice Validates collection parameters
     * @param params Collection parameters to validate
     */
    function _validateCollectionParams(CollectionParams memory params) internal pure {
        require(params.owner != address(0), "Zero address owner");
        require(bytes(params.name).length > 0, "Empty name");
        require(bytes(params.symbol).length > 0, "Empty symbol");
        require(params.maxSupply > 0, "Zero max supply");
    }

    /**
     * @notice Deploys a new collection proxy
     * @return proxyAddress Address of deployed proxy
     */
    function _deployCollectionProxy() internal returns (address proxyAddress) {
        proxyAddress = Clones.clone(erc1155CollectionImplementation);
    }

    /**
     * @notice Initializes the collection proxy
     * @param collectionAddr Address of the proxy
     * @param params Collection parameters
     */
    function _initializeCollection(address collectionAddr, CollectionParams memory params) internal {
        ERC1155CollectionImplementation(collectionAddr).initialize(params);
    }

    /**
     * @notice Registers the collection in factory mappings
     * @param collectionAddr Address of the collection
     */
    function _registerCollection(address collectionAddr) internal {
        s_validCollections[collectionAddr] = true;
        s_totalCollections++;
        emit ERC1155CollectionCreated(collectionAddr, msg.sender);
    }

    // ============ IMarketplaceCore Implementation ============

    function version() public pure override returns (string memory) {
        return "1.0.0";
    }

    function contractType() public pure override returns (string memory) {
        return "ERC1155CollectionFactory";
    }

    function isActive() public pure override returns (bool) {
        return true;
    }

    // ============ ICollectionFactory Implementation ============

    function getTotalCollections() external view override returns (uint256) {
        return s_totalCollections;
    }

    function isValidCollection(address collection) external view override returns (bool) {
        return s_validCollections[collection];
    }

    function getSupportedStandards() external pure override returns (string[] memory) {
        string[] memory standards = new string[](1);
        standards[0] = "ERC1155";
        return standards;
    }

    // ============ ERC165 Implementation ============

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ICollectionFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
