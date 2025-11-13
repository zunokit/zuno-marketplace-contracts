// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/errors/CollectionErrors.sol";
import "src/events/CollectionEvents.sol";

/**
 * @title CollectionVerifier
 * @notice Manages collection verification system for the NFT marketplace
 * @dev Handles verified collection registry, metadata management, and verification workflow
 * @author NFT Marketplace Team
 */
contract CollectionVerifier is Ownable, ReentrancyGuard, Pausable {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Access control contract
    MarketplaceAccessControl public accessControl;

    /// @notice Mapping from collection address to verification data
    mapping(address => CollectionVerification) public collectionVerifications;

    /// @notice Mapping from collection address to metadata
    mapping(address => CollectionMetadata) public collectionMetadata;

    /// @notice Array of all verified collections
    address[] public verifiedCollections;

    /// @notice Mapping to track verified collection indices for efficient removal
    mapping(address => uint256) public verifiedCollectionIndex;

    /// @notice Mapping from collection to verification requests
    mapping(address => VerificationRequest) public verificationRequests;

    /// @notice Array of pending verification requests
    address[] public pendingRequests;

    /// @notice Mapping to track pending request indices
    mapping(address => uint256) public pendingRequestIndex;

    /// @notice Whether verified-only mode is enabled
    bool public verifiedOnlyMode;

    /// @notice Verification fee (in wei)
    uint256 public verificationFee;

    /// @notice Fee recipient for verification fees
    address public feeRecipient;

    /// @notice Total number of verified collections
    uint256 public totalVerifiedCollections;

    /// @notice Total verification requests processed
    uint256 public totalRequestsProcessed;

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Collection verification data
     */
    struct CollectionVerification {
        bool isVerified; // Whether collection is verified
        VerificationStatus status; // Current verification status
        address verifiedBy; // Address that verified the collection
        uint256 verifiedAt; // Timestamp of verification
        uint256 expiryTimestamp; // When verification expires (0 = never)
        string verificationTier; // Verification tier (e.g., "Blue", "Gold")
        bytes32 verificationHash; // Hash of verification data
        bool hasSpecialBenefits; // Whether collection has special marketplace benefits
    }

    /**
     * @notice Collection metadata structure
     */
    struct CollectionMetadata {
        string name; // Collection name
        string description; // Collection description
        string imageUrl; // Collection image URL
        string websiteUrl; // Official website URL
        string twitterUrl; // Twitter URL
        string discordUrl; // Discord URL
        address creator; // Original creator address
        uint256 createdAt; // Creation timestamp
        string[] tags; // Collection tags/categories
        bool isActive; // Whether metadata is active
    }

    /**
     * @notice Verification request structure
     */
    struct VerificationRequest {
        address collection; // Collection address
        address requester; // Address that requested verification
        uint256 requestedAt; // Request timestamp
        VerificationStatus status; // Request status
        string submissionData; // Additional submission data/notes
        uint256 feePaid; // Fee paid for verification
        address reviewer; // Address reviewing the request
        string reviewNotes; // Review notes from verifier
    }

    /**
     * @notice Verification status enumeration
     */
    enum VerificationStatus {
        NONE, // No verification status
        PENDING, // Verification pending
        APPROVED, // Verification approved
        REJECTED, // Verification rejected
        EXPIRED, // Verification expired
        REVOKED // Verification revoked
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event CollectionVerified(
        address indexed collection, address indexed verifiedBy, string verificationTier, uint256 timestamp
    );

    event CollectionVerificationRevoked(
        address indexed collection, address indexed revokedBy, string reason, uint256 timestamp
    );

    event VerificationRequested(
        address indexed collection, address indexed requester, uint256 feePaid, uint256 timestamp
    );

    event VerificationRequestProcessed(
        address indexed collection, address indexed reviewer, VerificationStatus status, string reviewNotes
    );

    event CollectionMetadataUpdated(address indexed collection, address indexed updatedBy, uint256 timestamp);

    event VerifiedOnlyModeToggled(bool enabled, address toggledBy, uint256 timestamp);

    event VerificationFeeUpdated(uint256 oldFee, uint256 newFee, address updatedBy);

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures caller has required role
     */
    modifier onlyRole(bytes32 role) {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert Collection__UnauthorizedAccess();
        }
        _;
    }

    /**
     * @notice Ensures collection is a valid NFT contract
     */
    modifier validNFTContract(address collection) {
        if (!_isValidNFTContract(collection)) {
            revert Collection__InvalidNFTContract();
        }
        _;
    }

    /**
     * @notice Ensures collection is not already verified
     */
    modifier notAlreadyVerified(address collection) {
        if (collectionVerifications[collection].isVerified) {
            revert Collection__AlreadyVerified();
        }
        _;
    }

    /**
     * @notice Ensures collection is verified
     */
    modifier onlyVerified(address collection) {
        if (!isCollectionVerified(collection)) {
            revert Collection__NotVerified();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the CollectionVerifier
     * @param _accessControl Address of the access control contract
     * @param _feeRecipient Address to receive verification fees
     * @param _verificationFee Initial verification fee
     */
    constructor(address _accessControl, address _feeRecipient, uint256 _verificationFee) Ownable(msg.sender) {
        if (_accessControl == address(0) || _feeRecipient == address(0)) {
            revert Collection__ZeroAddress();
        }

        accessControl = MarketplaceAccessControl(_accessControl);
        feeRecipient = _feeRecipient;
        verificationFee = _verificationFee;
        verifiedOnlyMode = false;
    }

    // ============================================================================
    // VERIFICATION REQUEST FUNCTIONS
    // ============================================================================

    /**
     * @notice Requests verification for a collection
     * @param collection Address of the collection to verify
     * @param metadata Collection metadata
     * @param submissionData Additional submission data
     */
    function requestVerification(
        address collection,
        CollectionMetadata calldata metadata,
        string calldata submissionData
    ) external payable nonReentrant whenNotPaused validNFTContract(collection) notAlreadyVerified(collection) {
        // Check verification fee
        if (msg.value < verificationFee) {
            revert Collection__InsufficientFee();
        }

        // Check if request already exists
        if (verificationRequests[collection].status == VerificationStatus.PENDING) {
            revert Collection__RequestAlreadyPending();
        }

        // Create verification request
        verificationRequests[collection] = VerificationRequest({
            collection: collection,
            requester: msg.sender,
            requestedAt: block.timestamp,
            status: VerificationStatus.PENDING,
            submissionData: submissionData,
            feePaid: msg.value,
            reviewer: address(0),
            reviewNotes: ""
        });

        // Add to pending requests
        pendingRequestIndex[collection] = pendingRequests.length;
        pendingRequests.push(collection);

        // Store metadata
        CollectionMetadata storage storedMetadata = collectionMetadata[collection];
        storedMetadata.name = metadata.name;
        storedMetadata.description = metadata.description;
        storedMetadata.imageUrl = metadata.imageUrl;
        storedMetadata.websiteUrl = metadata.websiteUrl;
        storedMetadata.twitterUrl = metadata.twitterUrl;
        storedMetadata.discordUrl = metadata.discordUrl;
        storedMetadata.creator = msg.sender;
        storedMetadata.createdAt = block.timestamp;
        storedMetadata.isActive = true;

        // Copy tags array manually
        delete storedMetadata.tags;
        for (uint256 i = 0; i < metadata.tags.length; i++) {
            storedMetadata.tags.push(metadata.tags[i]);
        }

        // Transfer fee to recipient
        if (msg.value > 0) {
            (bool success,) = feeRecipient.call{value: msg.value}("");
            if (!success) {
                revert Collection__FeeTransferFailed();
            }
        }

        emit VerificationRequested(collection, msg.sender, msg.value, block.timestamp);
    }

    // ============================================================================
    // VERIFICATION PROCESSING FUNCTIONS
    // ============================================================================

    /**
     * @notice Processes a verification request (approve/reject)
     * @param collection Address of the collection
     * @param approve Whether to approve or reject
     * @param verificationTier Verification tier if approved
     * @param reviewNotes Review notes
     * @param expiryTimestamp Expiry timestamp (0 for no expiry)
     */
    function processVerificationRequest(
        address collection,
        bool approve,
        string calldata verificationTier,
        string calldata reviewNotes,
        uint256 expiryTimestamp
    ) external onlyRole(accessControl.VERIFIER_ROLE()) nonReentrant {
        VerificationRequest storage request = verificationRequests[collection];

        if (request.status != VerificationStatus.PENDING) {
            revert Collection__InvalidRequestStatus();
        }

        // Update request
        request.status = approve ? VerificationStatus.APPROVED : VerificationStatus.REJECTED;
        request.reviewer = msg.sender;
        request.reviewNotes = reviewNotes;

        if (approve) {
            // Create verification record
            collectionVerifications[collection] = CollectionVerification({
                isVerified: true,
                status: VerificationStatus.APPROVED,
                verifiedBy: msg.sender,
                verifiedAt: block.timestamp,
                expiryTimestamp: expiryTimestamp,
                verificationTier: verificationTier,
                verificationHash: _generateVerificationHash(collection, msg.sender, block.timestamp),
                hasSpecialBenefits: _determineSpecialBenefits(verificationTier)
            });

            // Add to verified collections array
            verifiedCollectionIndex[collection] = verifiedCollections.length;
            verifiedCollections.push(collection);
            totalVerifiedCollections++;

            emit CollectionVerified(collection, msg.sender, verificationTier, block.timestamp);
        }

        // Remove from pending requests
        _removePendingRequest(collection);
        totalRequestsProcessed++;

        emit VerificationRequestProcessed(collection, msg.sender, request.status, reviewNotes);
    }

    /**
     * @notice Revokes verification for a collection
     * @param collection Address of the collection
     * @param reason Reason for revocation
     */
    function revokeVerification(address collection, string calldata reason)
        external
        onlyRole(accessControl.MODERATOR_ROLE())
        nonReentrant
        onlyVerified(collection)
    {
        CollectionVerification storage verification = collectionVerifications[collection];

        // Update verification status
        verification.isVerified = false;
        verification.status = VerificationStatus.REVOKED;

        // Remove from verified collections array
        _removeVerifiedCollection(collection);
        totalVerifiedCollections--;

        emit CollectionVerificationRevoked(collection, msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Updates collection metadata
     * @param collection Address of the collection
     * @param metadata New metadata
     */
    function updateCollectionMetadata(address collection, CollectionMetadata calldata metadata) external nonReentrant {
        CollectionMetadata storage currentMetadata = collectionMetadata[collection];

        // Only creator or admin can update metadata
        if (msg.sender != currentMetadata.creator && !accessControl.hasRole(accessControl.ADMIN_ROLE(), msg.sender)) {
            revert Collection__UnauthorizedAccess();
        }

        // Update metadata
        currentMetadata.name = metadata.name;
        currentMetadata.description = metadata.description;
        currentMetadata.imageUrl = metadata.imageUrl;
        currentMetadata.websiteUrl = metadata.websiteUrl;
        currentMetadata.twitterUrl = metadata.twitterUrl;
        currentMetadata.discordUrl = metadata.discordUrl;
        currentMetadata.isActive = metadata.isActive;

        // Update tags array manually
        delete currentMetadata.tags;
        for (uint256 i = 0; i < metadata.tags.length; i++) {
            currentMetadata.tags.push(metadata.tags[i]);
        }

        emit CollectionMetadataUpdated(collection, msg.sender, block.timestamp);
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Toggles verified-only mode
     * @param enabled Whether to enable verified-only mode
     */
    function toggleVerifiedOnlyMode(bool enabled) external onlyRole(accessControl.ADMIN_ROLE()) {
        verifiedOnlyMode = enabled;
        emit VerifiedOnlyModeToggled(enabled, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates verification fee
     * @param newFee New verification fee
     */
    function updateVerificationFee(uint256 newFee) external onlyRole(accessControl.ADMIN_ROLE()) {
        uint256 oldFee = verificationFee;
        verificationFee = newFee;
        emit VerificationFeeUpdated(oldFee, newFee, msg.sender);
    }

    /**
     * @notice Updates fee recipient
     * @param newFeeRecipient New fee recipient address
     */
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(accessControl.ADMIN_ROLE()) {
        if (newFeeRecipient == address(0)) {
            revert Collection__ZeroAddress();
        }
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Emergency pause contract
     */
    function emergencyPause() external onlyRole(accessControl.EMERGENCY_ROLE()) {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(accessControl.ADMIN_ROLE()) {
        _unpause();
    }

    /**
     * @notice Batch verify collections (for migration)
     * @param collections Array of collection addresses
     * @param verificationTiers Array of verification tiers
     */
    function batchVerifyCollections(address[] calldata collections, string[] calldata verificationTiers)
        external
        onlyRole(accessControl.ADMIN_ROLE())
        nonReentrant
    {
        if (collections.length != verificationTiers.length || collections.length == 0) {
            revert Collection__InvalidArrayLength();
        }

        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];

            if (!collectionVerifications[collection].isVerified && _isValidNFTContract(collection)) {
                // Create verification record
                collectionVerifications[collection] = CollectionVerification({
                    isVerified: true,
                    status: VerificationStatus.APPROVED,
                    verifiedBy: msg.sender,
                    verifiedAt: block.timestamp,
                    expiryTimestamp: 0, // No expiry for batch verified
                    verificationTier: verificationTiers[i],
                    verificationHash: _generateVerificationHash(collection, msg.sender, block.timestamp),
                    hasSpecialBenefits: _determineSpecialBenefits(verificationTiers[i])
                });

                // Add to verified collections array
                verifiedCollectionIndex[collection] = verifiedCollections.length;
                verifiedCollections.push(collection);
                totalVerifiedCollections++;

                emit CollectionVerified(collection, msg.sender, verificationTiers[i], block.timestamp);
            }
        }
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Checks if a collection is verified and not expired
     * @param collection Address of the collection
     * @return isVerified Whether the collection is currently verified
     */
    function isCollectionVerified(address collection) public view returns (bool) {
        CollectionVerification memory verification = collectionVerifications[collection];

        if (!verification.isVerified || verification.status != VerificationStatus.APPROVED) {
            return false;
        }

        // Check if verification has expired
        if (verification.expiryTimestamp > 0 && block.timestamp > verification.expiryTimestamp) {
            return false;
        }

        return true;
    }

    /**
     * @notice Gets collection verification data
     * @param collection Address of the collection
     * @return verification Verification data
     */
    function getCollectionVerification(address collection)
        external
        view
        returns (CollectionVerification memory verification)
    {
        return collectionVerifications[collection];
    }

    /**
     * @notice Gets collection metadata
     * @param collection Address of the collection
     * @return metadata Collection metadata
     */
    function getCollectionMetadata(address collection) external view returns (CollectionMetadata memory metadata) {
        return collectionMetadata[collection];
    }

    /**
     * @notice Gets verification request data
     * @param collection Address of the collection
     * @return request Verification request data
     */
    function getVerificationRequest(address collection) external view returns (VerificationRequest memory request) {
        return verificationRequests[collection];
    }

    /**
     * @notice Gets all verified collections
     * @return collections Array of verified collection addresses
     */
    function getAllVerifiedCollections() external view returns (address[] memory collections) {
        return verifiedCollections;
    }

    /**
     * @notice Gets all pending verification requests
     * @return requests Array of pending request collection addresses
     */
    function getPendingRequests() external view returns (address[] memory requests) {
        return pendingRequests;
    }

    /**
     * @notice Gets paginated verified collections
     * @param offset Starting index
     * @param limit Number of collections to return
     * @return collections Array of collection addresses
     * @return total Total number of verified collections
     */
    function getVerifiedCollectionsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory collections, uint256 total)
    {
        total = verifiedCollections.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        collections = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            collections[i - offset] = verifiedCollections[i];
        }

        return (collections, total);
    }

    /**
     * @notice Checks if collection can be listed (based on verified-only mode)
     * @param collection Address of the collection
     * @return canList Whether the collection can be listed
     */
    function canCollectionBeListed(address collection) external view returns (bool canList) {
        if (!verifiedOnlyMode) {
            return true;
        }
        return isCollectionVerified(collection);
    }

    /**
     * @notice Gets verification statistics
     * @return totalVerified Total number of verified collections
     * @return totalRequests Total number of processed requests
     * @return pendingCount Number of pending requests
     * @return verifiedOnlyEnabled Whether verified-only mode is enabled
     */
    function getVerificationStats()
        external
        view
        returns (uint256 totalVerified, uint256 totalRequests, uint256 pendingCount, bool verifiedOnlyEnabled)
    {
        return (totalVerifiedCollections, totalRequestsProcessed, pendingRequests.length, verifiedOnlyMode);
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates if address is a valid NFT contract
     */
    function _isValidNFTContract(address collection) internal view returns (bool) {
        if (collection == address(0) || collection.code.length == 0) {
            return false;
        }

        try IERC165(collection).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
            if (isERC721) return true;
        } catch {}

        try IERC165(collection).supportsInterface(type(IERC1155).interfaceId) returns (bool isERC1155) {
            if (isERC1155) return true;
        } catch {}

        return false;
    }

    /**
     * @notice Generates verification hash
     */
    function _generateVerificationHash(address collection, address verifier, uint256 timestamp)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(collection, verifier, timestamp));
    }

    /**
     * @notice Determines if verification tier has special benefits
     */
    function _determineSpecialBenefits(string memory tier) internal pure returns (bool) {
        bytes32 tierHash = keccak256(abi.encodePacked(tier));
        return tierHash == keccak256("Gold") || tierHash == keccak256("Platinum");
    }

    /**
     * @notice Removes collection from pending requests array
     */
    function _removePendingRequest(address collection) internal {
        uint256 index = pendingRequestIndex[collection];
        uint256 lastIndex = pendingRequests.length - 1;

        if (index != lastIndex) {
            address lastCollection = pendingRequests[lastIndex];
            pendingRequests[index] = lastCollection;
            pendingRequestIndex[lastCollection] = index;
        }

        pendingRequests.pop();
        delete pendingRequestIndex[collection];
    }

    /**
     * @notice Removes collection from verified collections array
     */
    function _removeVerifiedCollection(address collection) internal {
        uint256 index = verifiedCollectionIndex[collection];
        uint256 lastIndex = verifiedCollections.length - 1;

        if (index != lastIndex) {
            address lastCollection = verifiedCollections[lastIndex];
            verifiedCollections[index] = lastCollection;
            verifiedCollectionIndex[lastCollection] = index;
        }

        verifiedCollections.pop();
        delete verifiedCollectionIndex[collection];
    }
}
