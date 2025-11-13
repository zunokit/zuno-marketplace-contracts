// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IExchangeRegistry} from "src/interfaces/registry/IExchangeRegistry.sol";
import {ICollectionRegistry} from "src/interfaces/registry/ICollectionRegistry.sol";
import {IFeeRegistry} from "src/interfaces/registry/IFeeRegistry.sol";
import {IAuctionRegistry} from "src/interfaces/registry/IAuctionRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title UserHub
 * @notice Read-only hub for frontend integration and user queries
 * @dev No admin functions, only view/query functions for users
 */
contract UserHub {
    // Registry contracts
    IExchangeRegistry public immutable exchangeRegistry;
    ICollectionRegistry public immutable collectionRegistry;
    IFeeRegistry public immutable feeRegistry;
    IAuctionRegistry public immutable auctionRegistry;

    // Core contracts
    address public immutable bundleManager;
    address public immutable offerManager;

    // Additional contracts (set by AdminHub)
    address public listingValidator;
    address public emergencyManager;
    address public accessControl;
    address public historyTracker;

    error UserHub__ZeroAddress();
    error UserHub__ContractNotSupported();

    constructor(
        address _exchangeRegistry,
        address _collectionRegistry,
        address _feeRegistry,
        address _auctionRegistry,
        address _bundleManager,
        address _offerManager
    ) {
        if (
            _exchangeRegistry == address(0) || _collectionRegistry == address(0) || _feeRegistry == address(0)
                || _auctionRegistry == address(0) || _bundleManager == address(0) || _offerManager == address(0)
        ) {
            revert UserHub__ZeroAddress();
        }

        exchangeRegistry = IExchangeRegistry(_exchangeRegistry);
        collectionRegistry = ICollectionRegistry(_collectionRegistry);
        feeRegistry = IFeeRegistry(_feeRegistry);
        auctionRegistry = IAuctionRegistry(_auctionRegistry);
        bundleManager = _bundleManager;
        offerManager = _offerManager;
    }

    /**
     * @notice Get all core contract addresses for frontend
     * @dev This is the main function frontends will use
     */
    function getAllAddresses()
        external
        view
        returns (
            address erc721Exchange,
            address erc1155Exchange,
            address erc721Factory,
            address erc1155Factory,
            address englishAuction,
            address dutchAuction,
            address auctionFactory,
            address feeRegistryAddr,
            address bundleManagerAddr,
            address offerManagerAddr
        )
    {
        return (
            exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC721),
            exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC1155),
            collectionRegistry.getFactory("ERC721"),
            collectionRegistry.getFactory("ERC1155"),
            auctionRegistry.getAuctionContract(IAuctionRegistry.AuctionType.ENGLISH),
            auctionRegistry.getAuctionContract(IAuctionRegistry.AuctionType.DUTCH),
            auctionRegistry.getAuctionFactory(),
            address(feeRegistry),
            bundleManager,
            offerManager
        );
    }

    /**
     * @notice Auto-detect and return appropriate exchange for NFT contract
     */
    function getExchangeFor(address nftContract) external view returns (address) {
        // Check ERC721
        try IERC165(nftContract).supportsInterface(0x80ac58cd) returns (bool supports721) {
            if (supports721) {
                return exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC721);
            }
        } catch {}

        // Check ERC1155
        try IERC165(nftContract).supportsInterface(0xd9b67a26) returns (bool supports1155) {
            if (supports1155) {
                return exchangeRegistry.getExchange(IExchangeRegistry.TokenStandard.ERC1155);
            }
        } catch {}

        revert UserHub__ContractNotSupported();
    }

    /**
     * @notice Get fee registry address for fee calculations
     */
    function getFeeRegistry() external view returns (address) {
        return address(feeRegistry);
    }

    /**
     * @notice Verify if collection is registered and valid
     */
    function verifyCollection(address collection) external view returns (bool) {
        // Implementation depends on CollectionVerifier
        if (accessControl != address(0)) {
            // Add collection verification logic here
            return true; // Placeholder
        }
        return false;
    }

    /**
     * @notice Get factory for collection type
     */
    function getFactoryFor(string memory tokenType) external view returns (address) {
        return collectionRegistry.getFactory(tokenType);
    }

    /**
     * @notice Get auction contract for auction type
     */
    function getAuctionFor(IAuctionRegistry.AuctionType auctionType) external view returns (address) {
        return auctionRegistry.getAuctionContract(auctionType);
    }

    /**
     * @notice Check if system is paused
     */
    function isPaused() external view returns (bool) {
        if (emergencyManager != address(0)) {
            // Add pause check logic here
            return false; // Placeholder
        }
        return false;
    }

    /**
     * @notice Update additional contracts (only callable by AdminHub)
     * @dev This allows AdminHub to update references after deployment
     */
    function updateAdditionalContracts(
        address _listingValidator,
        address _emergencyManager,
        address _accessControl,
        address _historyTracker
    ) external {
        // Only AdminHub should be able to call this
        require(msg.sender != address(0), "Invalid caller"); // Add proper access control

        listingValidator = _listingValidator;
        emergencyManager = _emergencyManager;
        accessControl = _accessControl;
        historyTracker = _historyTracker;
    }

    /**
     * @notice Get system health status
     */
    function getSystemStatus()
        external
        view
        returns (bool isHealthy, address[] memory activeContracts, uint256 timestamp)
    {
        activeContracts = new address[](6);
        activeContracts[0] = address(exchangeRegistry);
        activeContracts[1] = address(collectionRegistry);
        activeContracts[2] = address(feeRegistry);
        activeContracts[3] = address(auctionRegistry);
        activeContracts[4] = bundleManager;
        activeContracts[5] = offerManager;

        return (true, activeContracts, block.timestamp);
    }

    /**
     * @notice Get all additional contract addresses
     * @dev Returns addresses that were set via updateAdditionalContracts()
     */
    function getAdditionalAddresses()
        external
        view
        returns (
            address listingValidatorAddr,
            address emergencyManagerAddr,
            address accessControlAddr,
            address historyTrackerAddr
        )
    {
        return (listingValidator, emergencyManager, accessControl, historyTracker);
    }

    /**
     * @notice Get listing validator address
     */
    function getListingValidator() external view returns (address) {
        return listingValidator;
    }

    /**
     * @notice Get emergency manager address
     */
    function getEmergencyManager() external view returns (address) {
        return emergencyManager;
    }

    /**
     * @notice Get access control address
     */
    function getAccessControl() external view returns (address) {
        return accessControl;
    }

    /**
     * @notice Get history tracker address
     */
    function getHistoryTracker() external view returns (address) {
        return historyTracker;
    }

    /**
     * @notice Get bundle manager address
     */
    function getBundleManager() external view returns (address) {
        return bundleManager;
    }

    /**
     * @notice Get offer manager address
     */
    function getOfferManager() external view returns (address) {
        return offerManager;
    }

    /**
     * @notice Get all registries addresses
     */
    function getAllRegistries()
        external
        view
        returns (address exchange, address collection, address fee, address auction)
    {
        return (address(exchangeRegistry), address(collectionRegistry), address(feeRegistry), address(auctionRegistry));
    }
}
