// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ConfigManager
 * @notice Centralized configuration management for the marketplace
 * @dev Easily expandable for new settings and parameters
 */
contract ConfigManager is AccessControl {
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    // Config categories for organization
    enum ConfigCategory {
        FEES,
        LIMITS,
        TIMEOUTS,
        FEATURES,
        SECURITY,
        GOVERNANCE
    }

    // Config value types
    enum ConfigType {
        UINT256,
        BOOL,
        ADDRESS,
        STRING,
        BYTES32
    }

    // Config entry structure
    struct ConfigEntry {
        ConfigCategory category;
        ConfigType valueType;
        string description;
        uint256 lastUpdated;
        address updatedBy;
        bool exists;
    }

    // Storage for different types
    mapping(string => uint256) public uintConfigs;
    mapping(string => bool) public boolConfigs;
    mapping(string => address) public addressConfigs;
    mapping(string => string) public stringConfigs;
    mapping(string => bytes32) public bytes32Configs;

    // Metadata for configs
    mapping(string => ConfigEntry) public configMetadata;

    // Lists of config keys by category
    mapping(ConfigCategory => string[]) public configsByCategory;

    // All config keys
    string[] public allConfigKeys;

    // Events
    event ConfigSet(
        string indexed key, ConfigCategory indexed category, ConfigType indexed valueType, address updatedBy
    );
    event ConfigRemoved(string indexed key, address removedBy);

    constructor(address admin) {
        require(admin != address(0), "ConfigManager: Admin cannot be zero address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);

        // Initialize default configurations
        _initializeDefaults();
    }

    /**
     * @notice Set a uint256 configuration value
     */
    function setUintConfig(string calldata key, uint256 value, ConfigCategory category, string calldata description)
        external
        onlyRole(CONFIG_ADMIN_ROLE)
    {
        _setConfigMetadata(key, category, ConfigType.UINT256, description);
        uintConfigs[key] = value;
        emit ConfigSet(key, category, ConfigType.UINT256, msg.sender);
    }

    /**
     * @notice Set a boolean configuration value
     */
    function setBoolConfig(string calldata key, bool value, ConfigCategory category, string calldata description)
        external
        onlyRole(CONFIG_ADMIN_ROLE)
    {
        _setConfigMetadata(key, category, ConfigType.BOOL, description);
        boolConfigs[key] = value;
        emit ConfigSet(key, category, ConfigType.BOOL, msg.sender);
    }

    /**
     * @notice Set an address configuration value
     */
    function setAddressConfig(string calldata key, address value, ConfigCategory category, string calldata description)
        external
        onlyRole(CONFIG_ADMIN_ROLE)
    {
        _setConfigMetadata(key, category, ConfigType.ADDRESS, description);
        addressConfigs[key] = value;
        emit ConfigSet(key, category, ConfigType.ADDRESS, msg.sender);
    }

    /**
     * @notice Set a string configuration value
     */
    function setStringConfig(
        string calldata key,
        string calldata value,
        ConfigCategory category,
        string calldata description
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        _setConfigMetadata(key, category, ConfigType.STRING, description);
        stringConfigs[key] = value;
        emit ConfigSet(key, category, ConfigType.STRING, msg.sender);
    }

    /**
     * @notice Set a bytes32 configuration value
     */
    function setBytes32Config(string calldata key, bytes32 value, ConfigCategory category, string calldata description)
        external
        onlyRole(CONFIG_ADMIN_ROLE)
    {
        _setConfigMetadata(key, category, ConfigType.BYTES32, description);
        bytes32Configs[key] = value;
        emit ConfigSet(key, category, ConfigType.BYTES32, msg.sender);
    }

    /**
     * @notice Remove a configuration
     */
    function removeConfig(string calldata key) external onlyRole(CONFIG_ADMIN_ROLE) {
        require(configMetadata[key].exists, "ConfigManager: Config does not exist");

        // Clear the value based on type
        ConfigType valueType = configMetadata[key].valueType;
        if (valueType == ConfigType.UINT256) {
            delete uintConfigs[key];
        } else if (valueType == ConfigType.BOOL) {
            delete boolConfigs[key];
        } else if (valueType == ConfigType.ADDRESS) {
            delete addressConfigs[key];
        } else if (valueType == ConfigType.STRING) {
            delete stringConfigs[key];
        } else if (valueType == ConfigType.BYTES32) {
            delete bytes32Configs[key];
        }

        // Remove from category list
        ConfigCategory category = configMetadata[key].category;
        string[] storage categoryConfigs = configsByCategory[category];
        for (uint256 i = 0; i < categoryConfigs.length; i++) {
            if (keccak256(bytes(categoryConfigs[i])) == keccak256(bytes(key))) {
                categoryConfigs[i] = categoryConfigs[categoryConfigs.length - 1];
                categoryConfigs.pop();
                break;
            }
        }

        // Remove from all configs list
        for (uint256 i = 0; i < allConfigKeys.length; i++) {
            if (keccak256(bytes(allConfigKeys[i])) == keccak256(bytes(key))) {
                allConfigKeys[i] = allConfigKeys[allConfigKeys.length - 1];
                allConfigKeys.pop();
                break;
            }
        }

        delete configMetadata[key];
        emit ConfigRemoved(key, msg.sender);
    }

    /**
     * @notice Get all configurations in a category
     */
    function getConfigsByCategory(ConfigCategory category) external view returns (string[] memory keys) {
        return configsByCategory[category];
    }

    /**
     * @notice Get all configuration keys
     */
    function getAllConfigKeys() external view returns (string[] memory) {
        return allConfigKeys;
    }

    /**
     * @notice Check if a configuration exists
     */
    function configExists(string calldata key) external view returns (bool) {
        return configMetadata[key].exists;
    }

    /**
     * @notice Get configuration metadata
     */
    function getConfigMetadata(string calldata key)
        external
        view
        returns (
            ConfigCategory category,
            ConfigType valueType,
            string memory description,
            uint256 lastUpdated,
            address updatedBy,
            bool exists
        )
    {
        ConfigEntry memory entry = configMetadata[key];
        return (entry.category, entry.valueType, entry.description, entry.lastUpdated, entry.updatedBy, entry.exists);
    }

    /**
     * @notice Initialize default configuration values
     */
    function _initializeDefaults() internal {
        // Fee configurations
        _setAndStoreUint("marketplace.fee.taker", 200, ConfigCategory.FEES, "Taker fee in basis points");
        _setAndStoreUint("marketplace.fee.maker", 0, ConfigCategory.FEES, "Maker fee in basis points");
        _setAndStoreUint("marketplace.fee.max", 1000, ConfigCategory.FEES, "Maximum fee in basis points");

        // Limit configurations
        _setAndStoreUint("auction.duration.min", 1 hours, ConfigCategory.LIMITS, "Minimum auction duration");
        _setAndStoreUint("auction.duration.max", 30 days, ConfigCategory.LIMITS, "Maximum auction duration");
        _setAndStoreUint("listing.price.min", 0.001 ether, ConfigCategory.LIMITS, "Minimum listing price");

        // Security configurations
        _setAndStoreBool("emergency.pause.enabled", false, ConfigCategory.SECURITY, "Emergency pause status");
        _setAndStoreUint("timelock.delay", 48 hours, ConfigCategory.SECURITY, "Timelock delay for critical operations");

        // Feature flags
        _setAndStoreBool("features.bundles.enabled", true, ConfigCategory.FEATURES, "Bundle trading enabled");
        _setAndStoreBool("features.offers.enabled", true, ConfigCategory.FEATURES, "Offer system enabled");
        _setAndStoreBool("features.auctions.enabled", true, ConfigCategory.FEATURES, "Auction system enabled");
    }

    /**
     * @notice Internal helper to set config metadata
     */
    function _setConfigMetadata(
        string calldata key,
        ConfigCategory category,
        ConfigType valueType,
        string calldata description
    ) internal {
        if (!configMetadata[key].exists) {
            configsByCategory[category].push(key);
            allConfigKeys.push(key);
        }

        configMetadata[key] = ConfigEntry({
            category: category,
            valueType: valueType,
            description: description,
            lastUpdated: block.timestamp,
            updatedBy: msg.sender,
            exists: true
        });
    }

    /**
     * @notice Helper to set and store uint config during initialization
     */
    function _setAndStoreUint(string memory key, uint256 value, ConfigCategory category, string memory description)
        internal
    {
        uintConfigs[key] = value;
        configMetadata[key] = ConfigEntry({
            category: category,
            valueType: ConfigType.UINT256,
            description: description,
            lastUpdated: block.timestamp,
            updatedBy: msg.sender,
            exists: true
        });
        configsByCategory[category].push(key);
        allConfigKeys.push(key);
    }

    /**
     * @notice Helper to set and store bool config during initialization
     */
    function _setAndStoreBool(string memory key, bool value, ConfigCategory category, string memory description)
        internal
    {
        boolConfigs[key] = value;
        configMetadata[key] = ConfigEntry({
            category: category,
            valueType: ConfigType.BOOL,
            description: description,
            lastUpdated: block.timestamp,
            updatedBy: msg.sender,
            exists: true
        });
        configsByCategory[category].push(key);
        allConfigKeys.push(key);
    }
}
