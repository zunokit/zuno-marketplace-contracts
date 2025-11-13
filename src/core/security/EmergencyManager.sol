// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "src/core/validation/MarketplaceValidator.sol";
import "src/interfaces/IMarketplaceValidator.sol";
import "src/errors/EmergencyManagerErrors.sol";
import "src/events/EmergencyManagerEvents.sol";

/**
 * @title EmergencyManager
 * @notice Handles emergency functions and security measures for the marketplace
 * @dev Provides pausable functionality, emergency cancellations, and contract blacklisting
 * @author NFT Marketplace Team
 */
contract EmergencyManager is Ownable, Pausable, ReentrancyGuard {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Reference to the MarketplaceValidator contract
    MarketplaceValidator public immutable marketplaceValidator;

    /// @notice Mapping of blacklisted contracts
    mapping(address => bool) public blacklistedContracts;

    /// @notice Mapping of blacklisted users
    mapping(address => bool) public blacklistedUsers;

    /// @notice Emergency pause duration (24 hours default)
    uint256 public constant EMERGENCY_PAUSE_DURATION = 24 hours;

    /// @notice Last emergency pause timestamp
    uint256 public lastEmergencyPause;

    /// @notice Minimum time between emergency pauses (1 hour)
    uint256 public constant MIN_PAUSE_INTERVAL = 1 hours;

    // Events are imported from EmergencyManagerEvents.sol

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures contract is not blacklisted
     */
    modifier notBlacklistedContract(address contractAddr) {
        if (blacklistedContracts[contractAddr]) {
            revert EmergencyManager__ContractBlacklisted();
        }
        _;
    }

    /**
     * @notice Ensures user is not blacklisted
     */
    modifier notBlacklistedUser(address user) {
        if (blacklistedUsers[user]) {
            revert EmergencyManager__UserBlacklisted();
        }
        _;
    }

    /**
     * @notice Ensures minimum interval between emergency pauses
     */
    modifier emergencyPauseCooldown() {
        if (lastEmergencyPause != 0 && block.timestamp < lastEmergencyPause + MIN_PAUSE_INTERVAL) {
            revert EmergencyManager__PauseCooldownActive();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the EmergencyManager
     * @param _marketplaceValidator Address of the MarketplaceValidator contract
     */
    constructor(address _marketplaceValidator) Ownable(msg.sender) {
        if (_marketplaceValidator == address(0)) {
            revert EmergencyManager__ZeroAddress();
        }
        marketplaceValidator = MarketplaceValidator(_marketplaceValidator);
    }

    // ============================================================================
    // EMERGENCY PAUSE FUNCTIONS
    // ============================================================================

    /**
     * @notice Activates emergency pause
     * @param reason Reason for the emergency pause
     */
    function emergencyPause(string calldata reason) external onlyOwner emergencyPauseCooldown nonReentrant {
        _pause();
        lastEmergencyPause = block.timestamp;
        emit EmergencyPauseActivated(msg.sender, block.timestamp, reason);
    }

    /**
     * @notice Deactivates emergency pause
     */
    function emergencyUnpause() external onlyOwner nonReentrant {
        _unpause();
        emit EmergencyPauseDeactivated(msg.sender, block.timestamp);
    }

    // ============================================================================
    // BLACKLIST FUNCTIONS
    // ============================================================================

    /**
     * @notice Blacklists or unblacklists a contract
     * @param contractAddr Address of the contract
     * @param isBlacklisted Whether to blacklist or unblacklist
     * @param reason Reason for the action
     */
    function setContractBlacklist(address contractAddr, bool isBlacklisted, string calldata reason)
        external
        onlyOwner
        nonReentrant
    {
        if (contractAddr == address(0)) {
            revert EmergencyManager__ZeroAddress();
        }

        blacklistedContracts[contractAddr] = isBlacklisted;
        emit ContractBlacklisted(contractAddr, isBlacklisted, reason);
    }

    /**
     * @notice Blacklists or unblacklists a user
     * @param userAddr Address of the user
     * @param isBlacklisted Whether to blacklist or unblacklist
     * @param reason Reason for the action
     */
    function setUserBlacklist(address userAddr, bool isBlacklisted, string calldata reason)
        external
        onlyOwner
        nonReentrant
    {
        if (userAddr == address(0)) {
            revert EmergencyManager__ZeroAddress();
        }

        blacklistedUsers[userAddr] = isBlacklisted;
        emit UserBlacklisted(userAddr, isBlacklisted, reason);
    }

    /**
     * @notice Batch blacklist multiple contracts
     * @param contractAddrs Array of contract addresses
     * @param isBlacklisted Whether to blacklist or unblacklist
     * @param reason Reason for the action
     */
    function batchSetContractBlacklist(address[] calldata contractAddrs, bool isBlacklisted, string calldata reason)
        external
        onlyOwner
        nonReentrant
    {
        uint256 length = contractAddrs.length;
        if (length == 0) {
            revert EmergencyManager__EmptyArray();
        }

        for (uint256 i = 0; i < length; i++) {
            address contractAddr = contractAddrs[i];
            if (contractAddr == address(0)) {
                revert EmergencyManager__ZeroAddress();
            }
            blacklistedContracts[contractAddr] = isBlacklisted;
            emit ContractBlacklisted(contractAddr, isBlacklisted, reason);
        }
    }

    // ============================================================================
    // BULK NFT STATUS RESET FUNCTIONS
    // ============================================================================

    /**
     * @notice Emergency bulk reset NFT status
     * @param nftContracts Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @param owners Array of owner addresses
     */
    function emergencyBulkResetNFTStatus(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        address[] calldata owners
    ) external onlyOwner nonReentrant {
        uint256 length = nftContracts.length;

        // Validate input arrays
        _validateBulkResetInputs(nftContracts, tokenIds, owners);

        // Reset NFT status for each NFT
        for (uint256 i = 0; i < length; i++) {
            _resetSingleNFTStatus(nftContracts[i], tokenIds[i], owners[i]);
        }

        emit BulkNFTStatusReset(nftContracts, tokenIds, owners, length);
    }

    /**
     * @notice Emergency reset all NFTs for a specific collection
     * @param nftContract Address of the NFT contract
     * @param tokenIds Array of token IDs to reset
     * @param owners Array of corresponding owners
     */
    function emergencyResetCollection(address nftContract, uint256[] calldata tokenIds, address[] calldata owners)
        external
        onlyOwner
        nonReentrant
    {
        if (nftContract == address(0)) {
            revert EmergencyManager__ZeroAddress();
        }

        uint256 length = tokenIds.length;
        if (length == 0 || length != owners.length) {
            revert EmergencyManager__ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < length; i++) {
            _resetSingleNFTStatus(nftContract, tokenIds[i], owners[i]);
        }

        // Create arrays for event emission
        address[] memory contracts = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            contracts[i] = nftContract;
        }

        emit BulkNFTStatusReset(contracts, tokenIds, owners, length);
    }

    // ============================================================================
    // EMERGENCY FUND WITHDRAWAL
    // ============================================================================

    /**
     * @notice Emergency withdrawal of stuck funds
     * @param recipient Address to receive the funds
     * @param amount Amount to withdraw (0 for all)
     * @param reason Reason for withdrawal
     */
    function emergencyWithdraw(address payable recipient, uint256 amount, string calldata reason)
        external
        onlyOwner
        nonReentrant
    {
        if (recipient == address(0)) {
            revert EmergencyManager__ZeroAddress();
        }

        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) {
            revert EmergencyManager__NoFundsToWithdraw();
        }

        uint256 withdrawAmount = amount == 0 ? contractBalance : amount;
        if (withdrawAmount > contractBalance) {
            revert EmergencyManager__InsufficientBalance();
        }

        (bool success,) = recipient.call{value: withdrawAmount}("");
        if (!success) {
            revert EmergencyManager__WithdrawalFailed();
        }

        emit EmergencyFundWithdrawal(recipient, withdrawAmount, reason, block.timestamp);
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates inputs for bulk reset operations
     */
    function _validateBulkResetInputs(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        address[] calldata owners
    ) internal pure {
        uint256 length = nftContracts.length;

        if (length == 0) {
            revert EmergencyManager__EmptyArray();
        }

        if (length != tokenIds.length || length != owners.length) {
            revert EmergencyManager__ArrayLengthMismatch();
        }

        // Check for zero addresses
        for (uint256 i = 0; i < length; i++) {
            if (nftContracts[i] == address(0) || owners[i] == address(0)) {
                revert EmergencyManager__ZeroAddress();
            }
        }
    }

    /**
     * @notice Resets status for a single NFT
     */
    function _resetSingleNFTStatus(address nftContract, uint256 tokenId, address owner) internal {
        try marketplaceValidator.emergencyResetNFTStatus(nftContract, tokenId, owner) {
        // Success - status reset
        }
            catch {
            // Log but don't revert to allow partial success
            // Could emit a specific event for failed resets if needed
        }
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Checks if a contract is blacklisted
     */
    function isContractBlacklisted(address contractAddr) external view returns (bool) {
        return blacklistedContracts[contractAddr];
    }

    /**
     * @notice Checks if a user is blacklisted
     */
    function isUserBlacklisted(address userAddr) external view returns (bool) {
        return blacklistedUsers[userAddr];
    }

    /**
     * @notice Gets time remaining for pause cooldown
     */
    function getPauseCooldownRemaining() external view returns (uint256) {
        if (lastEmergencyPause == 0) {
            return 0;
        }

        uint256 nextAllowedPause = lastEmergencyPause + MIN_PAUSE_INTERVAL;
        if (block.timestamp >= nextAllowedPause) {
            return 0;
        }
        return nextAllowedPause - block.timestamp;
    }

    // ============================================================================
    // RECEIVE FUNCTION
    // ============================================================================

    /**
     * @notice Allows contract to receive ETH
     */
    receive() external payable {
        // Allow contract to receive ETH for emergency scenarios
    }
}
