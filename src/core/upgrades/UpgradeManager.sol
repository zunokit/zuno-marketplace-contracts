// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title UpgradeManager
 * @notice Manages system upgrades and new feature additions
 * @dev Designed to handle future expansions like new token standards, roles, features
 */
contract UpgradeManager is AccessControl {
    bytes32 public constant UPGRADE_ADMIN_ROLE = keccak256("UPGRADE_ADMIN_ROLE");

    // Versioning
    uint256 public currentVersion;
    string public versionString;

    // Feature registry for new additions
    mapping(string => address) public features;
    mapping(string => bool) public featureEnabled;
    string[] public featureList;

    // Token standard registry (extensible)
    mapping(string => address) public tokenStandardImplementations;
    mapping(string => bool) public supportedStandards;
    string[] public tokenStandards;

    // Module registry (for new marketplace modules)
    mapping(string => address) public modules;
    mapping(string => bool) public moduleActive;
    string[] public moduleList;

    // Upgrade proposals (for governance)
    struct UpgradeProposal {
        uint256 id;
        string description;
        address implementation;
        bytes data;
        uint256 proposedAt;
        uint256 executionDelay;
        bool executed;
        address proposer;
    }

    mapping(uint256 => UpgradeProposal) public upgradeProposals;
    uint256 public proposalCounter;
    uint256 public constant MIN_EXECUTION_DELAY = 48 hours;

    // Events
    event VersionUpdated(uint256 oldVersion, uint256 newVersion, string versionString);
    event FeatureAdded(string indexed featureName, address implementation);
    event FeatureEnabled(string indexed featureName, bool enabled);
    event TokenStandardAdded(string indexed standard, address implementation);
    event ModuleAdded(string indexed moduleName, address implementation);
    event ModuleActivated(string indexed moduleName, bool active);
    event UpgradeProposed(uint256 indexed proposalId, address proposer, string description);
    event UpgradeExecuted(uint256 indexed proposalId, address executor);

    constructor(address admin) {
        require(admin != address(0), "UpgradeManager: Admin cannot be zero address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADE_ADMIN_ROLE, admin);

        currentVersion = 1;
        versionString = "v1.0.0";

        emit VersionUpdated(0, 1, "v1.0.0");
    }

    /**
     * @notice Add a new feature to the system
     * @param featureName Name of the feature
     * @param implementation Contract address implementing the feature
     */
    function addFeature(string calldata featureName, address implementation) external onlyRole(UPGRADE_ADMIN_ROLE) {
        require(implementation != address(0), "UpgradeManager: Invalid implementation");
        require(features[featureName] == address(0), "UpgradeManager: Feature already exists");

        features[featureName] = implementation;
        featureEnabled[featureName] = true;
        featureList.push(featureName);

        emit FeatureAdded(featureName, implementation);
        emit FeatureEnabled(featureName, true);
    }

    /**
     * @notice Enable/disable a feature
     * @param featureName Name of the feature
     * @param enabled Whether the feature should be enabled
     */
    function setFeatureEnabled(string calldata featureName, bool enabled) external onlyRole(UPGRADE_ADMIN_ROLE) {
        require(features[featureName] != address(0), "UpgradeManager: Feature does not exist");
        featureEnabled[featureName] = enabled;
        emit FeatureEnabled(featureName, enabled);
    }

    /**
     * @notice Add support for a new token standard
     * @param standardName Name of the token standard (e.g., "ERC404", "ERC6551")
     * @param implementation Address of the implementation contract
     */
    function addTokenStandard(string calldata standardName, address implementation)
        external
        onlyRole(UPGRADE_ADMIN_ROLE)
    {
        require(implementation != address(0), "UpgradeManager: Invalid implementation");
        require(!supportedStandards[standardName], "UpgradeManager: Standard already supported");

        tokenStandardImplementations[standardName] = implementation;
        supportedStandards[standardName] = true;
        tokenStandards.push(standardName);

        emit TokenStandardAdded(standardName, implementation);
    }

    /**
     * @notice Add a new module to the system
     * @param moduleName Name of the module
     * @param implementation Contract address of the module
     */
    function addModule(string calldata moduleName, address implementation) external onlyRole(UPGRADE_ADMIN_ROLE) {
        require(implementation != address(0), "UpgradeManager: Invalid implementation");
        require(modules[moduleName] == address(0), "UpgradeManager: Module already exists");

        modules[moduleName] = implementation;
        moduleActive[moduleName] = true;
        moduleList.push(moduleName);

        emit ModuleAdded(moduleName, implementation);
        emit ModuleActivated(moduleName, true);
    }

    /**
     * @notice Activate/deactivate a module
     * @param moduleName Name of the module
     * @param active Whether the module should be active
     */
    function setModuleActive(string calldata moduleName, bool active) external onlyRole(UPGRADE_ADMIN_ROLE) {
        require(modules[moduleName] != address(0), "UpgradeManager: Module does not exist");
        moduleActive[moduleName] = active;
        emit ModuleActivated(moduleName, active);
    }

    /**
     * @notice Propose a system upgrade
     * @param description Description of the upgrade
     * @param implementation New implementation address
     * @param data Initialization data for the upgrade
     * @param executionDelay Delay before execution (minimum 48 hours)
     */
    function proposeUpgrade(
        string calldata description,
        address implementation,
        bytes calldata data,
        uint256 executionDelay
    ) external onlyRole(UPGRADE_ADMIN_ROLE) returns (uint256 proposalId) {
        require(implementation != address(0), "UpgradeManager: Invalid implementation");
        require(executionDelay >= MIN_EXECUTION_DELAY, "UpgradeManager: Execution delay too short");

        proposalId = ++proposalCounter;

        upgradeProposals[proposalId] = UpgradeProposal({
            id: proposalId,
            description: description,
            implementation: implementation,
            data: data,
            proposedAt: block.timestamp,
            executionDelay: executionDelay,
            executed: false,
            proposer: msg.sender
        });

        emit UpgradeProposed(proposalId, msg.sender, description);
        return proposalId;
    }

    /**
     * @notice Execute an approved upgrade proposal
     * @param proposalId ID of the proposal to execute
     */
    function executeUpgrade(uint256 proposalId) external onlyRole(UPGRADE_ADMIN_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];

        require(proposal.id != 0, "UpgradeManager: Proposal does not exist");
        require(!proposal.executed, "UpgradeManager: Proposal already executed");
        require(
            block.timestamp >= proposal.proposedAt + proposal.executionDelay, "UpgradeManager: Execution delay not met"
        );

        proposal.executed = true;

        // Execute the upgrade (this would be customized based on the specific upgrade)
        // For now, we just mark it as executed and emit an event
        emit UpgradeExecuted(proposalId, msg.sender);
    }

    /**
     * @notice Update system version
     * @param newVersion New version number
     * @param newVersionString Human-readable version string
     */
    function updateVersion(uint256 newVersion, string calldata newVersionString) external onlyRole(UPGRADE_ADMIN_ROLE) {
        require(newVersion > currentVersion, "UpgradeManager: Version must be higher");

        uint256 oldVersion = currentVersion;
        currentVersion = newVersion;
        versionString = newVersionString;

        emit VersionUpdated(oldVersion, newVersion, newVersionString);
    }

    /**
     * @notice Get all supported features
     * @return featureNames Array of all feature names
     * @return implementations Array of corresponding implementation addresses
     * @return enabled Array of enabled status for each feature
     */
    function getAllFeatures()
        external
        view
        returns (string[] memory featureNames, address[] memory implementations, bool[] memory enabled)
    {
        uint256 length = featureList.length;
        featureNames = new string[](length);
        implementations = new address[](length);
        enabled = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            featureNames[i] = featureList[i];
            implementations[i] = features[featureList[i]];
            enabled[i] = featureEnabled[featureList[i]];
        }

        return (featureNames, implementations, enabled);
    }

    /**
     * @notice Get all supported token standards
     * @return standardNames Array of token standard names
     * @return implementations Array of implementation addresses
     */
    function getAllTokenStandards()
        external
        view
        returns (string[] memory standardNames, address[] memory implementations)
    {
        uint256 length = tokenStandards.length;
        standardNames = new string[](length);
        implementations = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            standardNames[i] = tokenStandards[i];
            implementations[i] = tokenStandardImplementations[tokenStandards[i]];
        }

        return (standardNames, implementations);
    }

    /**
     * @notice Get all modules
     * @return moduleNames Array of module names
     * @return implementations Array of implementation addresses
     * @return active Array of active status for each module
     */
    function getAllModules()
        external
        view
        returns (string[] memory moduleNames, address[] memory implementations, bool[] memory active)
    {
        uint256 length = moduleList.length;
        moduleNames = new string[](length);
        implementations = new address[](length);
        active = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            moduleNames[i] = moduleList[i];
            implementations[i] = modules[moduleList[i]];
            active[i] = moduleActive[moduleList[i]];
        }

        return (moduleNames, implementations, active);
    }

    /**
     * @notice Check if a feature is available and enabled
     * @param featureName Name of the feature
     * @return available Whether the feature exists and is enabled
     */
    function isFeatureAvailable(string calldata featureName) external view returns (bool available) {
        return features[featureName] != address(0) && featureEnabled[featureName];
    }
}
