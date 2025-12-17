// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import {IExchangeRegistry} from "src/interfaces/registry/IExchangeRegistry.sol";
import {ICollectionRegistry} from "src/interfaces/registry/ICollectionRegistry.sol";
import {IFeeRegistry} from "src/interfaces/registry/IFeeRegistry.sol";
import {IAuctionRegistry} from "src/interfaces/registry/IAuctionRegistry.sol";

/**
 * @title AdminHub
 * @notice Admin-only functions for marketplace management
 * @dev Separate from UserHub for better security separation
 */
contract AdminHub is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Registry contracts
    IExchangeRegistry public immutable exchangeRegistry;
    ICollectionRegistry public immutable collectionRegistry;
    IFeeRegistry public immutable feeRegistry;
    IAuctionRegistry public immutable auctionRegistry;

    // Additional contracts
    address public listingValidator;
    address public emergencyManager;
    address public accessControl;
    address public historyTracker;

    // Management contracts addresses for extensibility
    address public roleManager;
    address public upgradeManager;
    address public configManager;

    event ContractsConfigured(
        address listingValidator, address emergencyManager, address accessControl, address historyTracker
    );

    constructor(
        address admin,
        address _exchangeRegistry,
        address _collectionRegistry,
        address _feeRegistry,
        address _auctionRegistry
    ) {
        require(admin != address(0), "Admin cannot be zero");
        require(_exchangeRegistry != address(0), "ExchangeRegistry cannot be zero");
        require(_collectionRegistry != address(0), "CollectionRegistry cannot be zero");
        require(_feeRegistry != address(0), "FeeRegistry cannot be zero");
        require(_auctionRegistry != address(0), "AuctionRegistry cannot be zero");

        // Grant roles to admin (permanent)
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        // Also grant roles to deployer (msg.sender) for initial setup if different from admin
        // Deployer should revoke their own roles after deployment completes
        if (msg.sender != admin) {
            _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
            _grantRole(ADMIN_ROLE, msg.sender);
        }

        exchangeRegistry = IExchangeRegistry(_exchangeRegistry);
        collectionRegistry = ICollectionRegistry(_collectionRegistry);
        feeRegistry = IFeeRegistry(_feeRegistry);
        auctionRegistry = IAuctionRegistry(_auctionRegistry);
    }

    /**
     * @notice Set additional contracts (call after constructor)
     * @dev Can only be called by admin
     */
    function setAdditionalContracts(
        address _listingValidator,
        address _emergencyManager,
        address _accessControl,
        address _historyTracker
    ) external onlyRole(ADMIN_ROLE) {
        listingValidator = _listingValidator;
        emergencyManager = _emergencyManager;
        accessControl = _accessControl;
        historyTracker = _historyTracker;

        emit ContractsConfigured(_listingValidator, _emergencyManager, _accessControl, _historyTracker);
    }

    /**
     * @notice Register exchange
     */
    function registerExchange(IExchangeRegistry.TokenStandard standard, address exchange)
        external
        onlyRole(ADMIN_ROLE)
    {
        exchangeRegistry.registerExchange(standard, exchange);
    }

    /**
     * @notice Register factory
     */
    function registerCollectionFactory(string memory tokenType, address factory) external onlyRole(ADMIN_ROLE) {
        collectionRegistry.registerFactory(tokenType, factory);
    }

    /**
     * @notice Register auction
     */
    function registerAuction(IAuctionRegistry.AuctionType auctionType, address auction) external onlyRole(ADMIN_ROLE) {
        auctionRegistry.registerAuction(auctionType, auction);
    }

    /**
     * @notice Update auction factory
     */
    function updateAuctionFactory(address factory) external onlyRole(ADMIN_ROLE) {
        auctionRegistry.updateAuctionFactory(factory);
    }

    /**
     * @notice Emergency pause all operations
     */
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        // Implementation depends on EmergencyManager interface
        require(emergencyManager != address(0), "Emergency manager not set");
        // Add emergency pause logic here
    }

    /**
     * @notice Get all registry addresses
     */
    function getAllRegistries()
        external
        view
        returns (address exchange, address collection, address fee, address auction)
    {
        return (address(exchangeRegistry), address(collectionRegistry), address(feeRegistry), address(auctionRegistry));
    }

    /**
     * @notice Set management contract addresses
     */
    function setManagementContracts(address _roleManager, address _upgradeManager, address _configManager)
        external
        onlyRole(ADMIN_ROLE)
    {
        roleManager = _roleManager;
        upgradeManager = _upgradeManager;
        configManager = _configManager;
    }

    /**
     * @notice Get management contracts
     */
    function getManagementContracts() external view returns (address, address, address) {
        return (roleManager, upgradeManager, configManager);
    }
}
