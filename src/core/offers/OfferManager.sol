// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/core/fees/AdvancedFeeManager.sol";
// Import Offer types from centralized location
// Note: OfferManager has its own Offer struct with different fields, keeping local version
import "src/errors/NFTExchangeErrors.sol";
import "src/events/NFTExchangeEvents.sol";
import "src/libraries/NFTTransferLib.sol";
import "src/libraries/NFTValidationLib.sol";
import "src/libraries/PaymentDistributionLib.sol";

/**
 * @title OfferManager
 * @notice Comprehensive offer and bidding system for NFT marketplace
 * @dev Supports individual NFT offers, collection offers, and trait-based offers
 * @author NFT Marketplace Team
 */
contract OfferManager is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Access control contract
    MarketplaceAccessControl public accessControl;

    /// @notice Fee manager contract
    AdvancedFeeManager public feeManager;

    /// @notice Individual NFT offers
    mapping(bytes32 => Offer) public nftOffers;
    mapping(bytes32 => OfferTiming) public nftOfferTiming;
    mapping(bytes32 => OfferDetails) public nftOfferDetails;

    /// @notice Collection-wide offers
    mapping(bytes32 => CollectionOffer) public collectionOffers;
    mapping(bytes32 => CollectionOfferProgress) public collectionOfferProgress;
    mapping(bytes32 => mapping(uint256 => bool)) public excludedTokens;

    /// @notice Trait-based offers
    mapping(bytes32 => TraitOffer) public traitOffers;
    mapping(bytes32 => TraitOfferDetails) public traitOfferDetails;

    /// @notice User's active offers
    mapping(address => bytes32[]) public userOffers;

    /// @notice NFT's received offers
    mapping(address => mapping(uint256 => bytes32[])) public nftOfferIds;

    /// @notice Track token IDs with offers for each collection (gas optimization)
    mapping(address => EnumerableSet.UintSet) private _collectionTokenIds;

    /// @notice Collection's received offers
    mapping(address => bytes32[]) public collectionOfferIds;

    /// @notice Offer counter for unique IDs
    uint256 public offerCounter;

    /// @notice Total offers created
    uint256 public totalOffersCreated;

    /// @notice Total offers accepted
    uint256 public totalOffersAccepted;

    /// @notice Active offer tracking arrays
    bytes32[] public activeNFTOffers;
    bytes32[] public activeCollectionOffers;
    bytes32[] public activeTraitOffers;

    /// @notice Mapping to track offer index in active arrays
    mapping(bytes32 => uint256) public activeOfferIndex;

    /// @notice Minimum offer duration (1 hour)
    uint256 public constant MIN_OFFER_DURATION = 1 hours;

    /// @notice Maximum offer duration (30 days)
    uint256 public constant MAX_OFFER_DURATION = 30 days;

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Individual NFT offer - Core data only
     */
    struct Offer {
        bytes32 offerId; // Unique offer identifier
        address offerer; // Address making the offer
        address collection; // NFT collection address
        uint256 tokenId; // Specific token ID
        uint256 amount; // Offer amount
        OfferStatus status; // Current offer status
    }

    /**
     * @notice Offer timing information
     */
    struct OfferTiming {
        uint256 expiration; // Offer expiration timestamp
        uint256 createdAt; // Creation timestamp
        uint256 acceptedAt; // Acceptance timestamp (if accepted)
    }

    /**
     * @notice Offer details
     */
    struct OfferDetails {
        address paymentToken; // Payment token (ETH = address(0))
        address acceptedBy; // Who accepted the offer
    }

    /**
     * @notice Collection-wide offer - Core data only
     */
    struct CollectionOffer {
        bytes32 offerId; // Unique offer identifier
        address offerer; // Address making the offer
        address collection; // NFT collection address
        uint256 amount; // Offer amount per NFT
        uint256 quantity; // Number of NFTs wanted
        OfferStatus status; // Current offer status
    }

    /**
     * @notice Collection offer progress
     */
    struct CollectionOfferProgress {
        uint256 filled; // Number of NFTs already purchased
        uint256 expiration; // Offer expiration timestamp
        uint256 createdAt; // Creation timestamp
        address paymentToken; // Payment token (ETH = address(0))
    }

    /**
     * @notice Trait-based offer - Core data only
     */
    struct TraitOffer {
        bytes32 offerId; // Unique offer identifier
        address offerer; // Address making the offer
        address collection; // NFT collection address
        uint256 amount; // Offer amount per NFT
        uint256 quantity; // Number of NFTs wanted
        OfferStatus status; // Current offer status
    }

    /**
     * @notice Trait offer details
     */
    struct TraitOfferDetails {
        string traitType; // Trait type (e.g., "Background")
        string traitValue; // Trait value (e.g., "Blue")
        address paymentToken; // Payment token (ETH = address(0))
        uint256 expiration; // Offer expiration timestamp
        uint256 createdAt; // Creation timestamp
        uint256 filled; // Number of NFTs already purchased
    }

    /**
     * @notice Offer status enumeration
     */
    enum OfferStatus {
        ACTIVE,
        ACCEPTED,
        CANCELLED,
        EXPIRED
    }

    /**
     * @notice Offer type enumeration
     */
    enum OfferType {
        NFT_OFFER,
        COLLECTION_OFFER,
        TRAIT_OFFER
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event OfferCreated(
        bytes32 indexed offerId,
        address indexed offerer,
        address indexed collection,
        uint256 tokenId,
        uint256 amount,
        OfferType offerType
    );

    event OfferAccepted(
        bytes32 indexed offerId, address indexed accepter, address indexed collection, uint256 tokenId, uint256 amount
    );

    event OfferCancelled(bytes32 indexed offerId, address indexed offerer, string reason);

    event OfferExpired(bytes32 indexed offerId, address indexed offerer);

    event CollectionOfferFilled(
        bytes32 indexed offerId, address indexed seller, uint256 indexed tokenId, uint256 amount
    );

    event TraitOfferFilled(
        bytes32 indexed offerId, address indexed seller, uint256 indexed tokenId, string traitType, string traitValue
    );

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures caller has required role
     */
    modifier onlyRole(bytes32 role) {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert NFTExchange__InvalidOwner();
        }
        _;
    }

    /**
     * @notice Validates offer parameters
     */
    modifier validOfferParams(address collection, uint256 amount, uint256 expiration) {
        if (collection == address(0)) {
            revert NFTExchange__InvalidCollection();
        }
        if (amount == 0) {
            revert NFTExchange__InvalidPrice();
        }
        if (expiration <= block.timestamp + MIN_OFFER_DURATION || expiration > block.timestamp + MAX_OFFER_DURATION) {
            revert NFTExchange__InvalidDuration();
        }
        _;
    }

    /**
     * @notice Ensures offer exists and is active
     */
    modifier offerExists(bytes32 offerId) {
        if (nftOffers[offerId].offerId == bytes32(0)) {
            revert NFTExchange__InvalidListing();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the OfferManager
     * @param _accessControl Address of the access control contract
     * @param _feeManager Address of the fee manager contract
     */
    constructor(address _accessControl, address _feeManager) Ownable(msg.sender) {
        if (_accessControl == address(0) || _feeManager == address(0)) {
            revert NFTExchange__NotTheOwner();
        }

        accessControl = MarketplaceAccessControl(_accessControl);
        feeManager = AdvancedFeeManager(_feeManager);
        offerCounter = 1;
    }

    // ============================================================================
    // OFFER CREATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates an offer for a specific NFT
     * @param collection NFT collection address
     * @param tokenId Specific token ID
     * @param paymentToken Payment token address (address(0) for ETH)
     * @param amount Offer amount
     * @param expiration Offer expiration timestamp
     * @return offerId Unique offer identifier
     */
    function createNFTOffer(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 amount,
        uint256 expiration
    )
        external
        payable
        nonReentrant
        whenNotPaused
        validOfferParams(collection, amount, expiration)
        returns (bytes32 offerId)
    {
        offerId = _generateOfferId();

        // Handle payment escrow
        if (paymentToken == address(0)) {
            // ETH offer
            if (msg.value != amount) {
                revert NFTExchange__InvalidPrice();
            }
        } else {
            // ERC20 offer
            IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Create offer
        nftOffers[offerId] = Offer({
            offerId: offerId,
            offerer: msg.sender,
            collection: collection,
            tokenId: tokenId,
            amount: amount,
            status: OfferStatus.ACTIVE
        });

        // Set timing information
        nftOfferTiming[offerId] = OfferTiming({expiration: expiration, createdAt: block.timestamp, acceptedAt: 0});

        // Set details
        nftOfferDetails[offerId] = OfferDetails({paymentToken: paymentToken, acceptedBy: address(0)});

        // Update mappings
        userOffers[msg.sender].push(offerId);
        nftOfferIds[collection][tokenId].push(offerId);

        // Track token ID in EnumerableSet for gas-efficient queries
        _collectionTokenIds[collection].add(tokenId);

        // Add to active offers tracking
        activeNFTOffers.push(offerId);
        activeOfferIndex[offerId] = activeNFTOffers.length - 1;

        totalOffersCreated++;

        emit OfferCreated(offerId, msg.sender, collection, tokenId, amount, OfferType.NFT_OFFER);

        return offerId;
    }

    /**
     * @notice Creates a collection-wide offer
     * @param collection NFT collection address
     * @param paymentToken Payment token address
     * @param amount Offer amount per NFT
     * @param quantity Number of NFTs wanted
     * @param expiration Offer expiration timestamp
     * @return offerId Unique offer identifier
     */
    function createCollectionOffer(
        address collection,
        address paymentToken,
        uint256 amount,
        uint256 quantity,
        uint256 expiration
    )
        external
        payable
        nonReentrant
        whenNotPaused
        validOfferParams(collection, amount, expiration)
        returns (bytes32 offerId)
    {
        if (quantity == 0 || quantity > 100) {
            revert NFTExchange__InvalidQuantity();
        }

        offerId = _generateOfferId();
        uint256 totalAmount = amount * quantity;

        // Handle payment escrow
        if (paymentToken == address(0)) {
            // ETH offer
            if (msg.value != totalAmount) {
                revert NFTExchange__InvalidPrice();
            }
        } else {
            // ERC20 offer
            IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        // Create collection offer
        collectionOffers[offerId] = CollectionOffer({
            offerId: offerId,
            offerer: msg.sender,
            collection: collection,
            amount: amount,
            quantity: quantity,
            status: OfferStatus.ACTIVE
        });

        // Set progress information
        collectionOfferProgress[offerId] = CollectionOfferProgress({
            filled: 0, expiration: expiration, createdAt: block.timestamp, paymentToken: paymentToken
        });

        // Update mappings
        userOffers[msg.sender].push(offerId);
        collectionOfferIds[collection].push(offerId);

        // Add to active offers tracking
        activeCollectionOffers.push(offerId);
        activeOfferIndex[offerId] = activeCollectionOffers.length - 1;

        totalOffersCreated++;

        emit OfferCreated(
            offerId,
            msg.sender,
            collection,
            0, // No specific token ID for collection offers
            amount,
            OfferType.COLLECTION_OFFER
        );

        return offerId;
    }

    /**
     * @notice Creates a trait-based offer
     * @param collection NFT collection address
     * @param traitType Trait type (e.g., "Background")
     * @param traitValue Trait value (e.g., "Blue")
     * @param paymentToken Payment token address
     * @param amount Offer amount per NFT
     * @param quantity Number of NFTs wanted
     * @param expiration Offer expiration timestamp
     * @return offerId Unique offer identifier
     */
    function createTraitOffer(
        address collection,
        string calldata traitType,
        string calldata traitValue,
        address paymentToken,
        uint256 amount,
        uint256 quantity,
        uint256 expiration
    )
        external
        payable
        nonReentrant
        whenNotPaused
        validOfferParams(collection, amount, expiration)
        returns (bytes32 offerId)
    {
        if (quantity == 0 || quantity > 50) {
            revert NFTExchange__InvalidQuantity();
        }

        if (bytes(traitType).length == 0 || bytes(traitValue).length == 0) {
            revert NFTExchange__InvalidParameters();
        }

        offerId = _generateOfferId();
        uint256 totalAmount = amount * quantity;

        // Handle payment escrow
        if (paymentToken == address(0)) {
            // ETH offer
            if (msg.value != totalAmount) {
                revert NFTExchange__InvalidPrice();
            }
        } else {
            // ERC20 offer
            IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        // Create trait offer
        traitOffers[offerId] = TraitOffer({
            offerId: offerId,
            offerer: msg.sender,
            collection: collection,
            amount: amount,
            quantity: quantity,
            status: OfferStatus.ACTIVE
        });

        // Set trait details
        traitOfferDetails[offerId] = TraitOfferDetails({
            traitType: traitType,
            traitValue: traitValue,
            paymentToken: paymentToken,
            expiration: expiration,
            createdAt: block.timestamp,
            filled: 0
        });

        // Update mappings
        userOffers[msg.sender].push(offerId);

        // Add to active offers tracking
        activeTraitOffers.push(offerId);
        activeOfferIndex[offerId] = activeTraitOffers.length - 1;

        totalOffersCreated++;

        emit OfferCreated(
            offerId,
            msg.sender,
            collection,
            0, // No specific token ID for trait offers
            amount,
            OfferType.TRAIT_OFFER
        );

        return offerId;
    }

    // ============================================================================
    // OFFER ACCEPTANCE FUNCTIONS
    // ============================================================================

    /**
     * @notice Accepts an NFT offer
     * @param offerId Offer identifier
     */
    function acceptNFTOffer(bytes32 offerId) external nonReentrant whenNotPaused offerExists(offerId) {
        Offer storage offer = nftOffers[offerId];
        OfferTiming storage timing = nftOfferTiming[offerId];
        OfferDetails storage details = nftOfferDetails[offerId];

        if (offer.status != OfferStatus.ACTIVE) {
            revert NFTExchange__InvalidListing();
        }

        if (block.timestamp > timing.expiration) {
            offer.status = OfferStatus.EXPIRED;
            revert NFTExchange__ListingExpired();
        }

        // Verify ownership and transfer NFT
        _transferNFT(offer.collection, offer.tokenId, msg.sender, offer.offerer);

        // Calculate and distribute fees
        uint256 netAmount = _processPayment(
            offer.collection, offer.tokenId, offer.amount, details.paymentToken, offer.offerer, msg.sender
        );

        // Update offer status
        offer.status = OfferStatus.ACCEPTED;
        timing.acceptedAt = block.timestamp;
        details.acceptedBy = msg.sender;

        totalOffersAccepted++;

        emit OfferAccepted(offerId, msg.sender, offer.collection, offer.tokenId, offer.amount);
    }

    /**
     * @notice Accepts a collection offer by selling an NFT
     * @param offerId Collection offer identifier
     * @param tokenId Token ID to sell
     */
    function acceptCollectionOffer(bytes32 offerId, uint256 tokenId) external nonReentrant whenNotPaused {
        CollectionOffer storage offer = collectionOffers[offerId];
        CollectionOfferProgress storage progress = collectionOfferProgress[offerId];

        if (offer.offerId == bytes32(0) || offer.status != OfferStatus.ACTIVE) {
            revert NFTExchange__InvalidListing();
        }

        if (block.timestamp > progress.expiration) {
            offer.status = OfferStatus.EXPIRED;
            revert NFTExchange__ListingExpired();
        }

        if (progress.filled >= offer.quantity) {
            revert NFTExchange__InvalidQuantity();
        }

        if (excludedTokens[offerId][tokenId]) {
            revert NFTExchange__InvalidParameters();
        }

        // Verify ownership and transfer NFT
        _transferNFT(offer.collection, tokenId, msg.sender, offer.offerer);

        // Calculate and distribute payment
        uint256 netAmount =
            _processPayment(offer.collection, tokenId, offer.amount, progress.paymentToken, offer.offerer, msg.sender);

        // Update offer
        progress.filled++;
        if (progress.filled >= offer.quantity) {
            offer.status = OfferStatus.ACCEPTED;
        }

        emit CollectionOfferFilled(offerId, msg.sender, tokenId, offer.amount);
    }

    /**
     * @notice Cancels an offer
     * @param offerId Offer identifier
     * @param reason Cancellation reason
     */
    function cancelOffer(bytes32 offerId, string calldata reason) external nonReentrant {
        // Check NFT offer first
        if (nftOffers[offerId].offerId != bytes32(0)) {
            Offer storage offer = nftOffers[offerId];
            OfferDetails storage details = nftOfferDetails[offerId];

            if (offer.offerer != msg.sender) {
                revert NFTExchange__InvalidOwner();
            }

            if (offer.status != OfferStatus.ACTIVE) {
                revert NFTExchange__InvalidListing();
            }

            offer.status = OfferStatus.CANCELLED;

            // Refund payment
            _refundPayment(details.paymentToken, offer.amount, offer.offerer);

            emit OfferCancelled(offerId, msg.sender, reason);
            return;
        }

        // Check collection offer
        if (collectionOffers[offerId].offerId != bytes32(0)) {
            CollectionOffer storage offer = collectionOffers[offerId];
            CollectionOfferProgress storage progress = collectionOfferProgress[offerId];

            if (offer.offerer != msg.sender) {
                revert NFTExchange__InvalidOwner();
            }

            if (offer.status != OfferStatus.ACTIVE) {
                revert NFTExchange__InvalidListing();
            }

            offer.status = OfferStatus.CANCELLED;

            // Refund remaining payment
            uint256 remainingAmount = (offer.quantity - progress.filled) * offer.amount;
            _refundPayment(progress.paymentToken, remainingAmount, offer.offerer);

            emit OfferCancelled(offerId, msg.sender, reason);
            return;
        }

        // Check trait offer
        if (traitOffers[offerId].offerId != bytes32(0)) {
            TraitOffer storage offer = traitOffers[offerId];
            TraitOfferDetails storage details = traitOfferDetails[offerId];

            if (offer.offerer != msg.sender) {
                revert NFTExchange__InvalidOwner();
            }

            if (offer.status != OfferStatus.ACTIVE) {
                revert NFTExchange__InvalidListing();
            }

            offer.status = OfferStatus.CANCELLED;

            // Refund remaining payment
            uint256 remainingAmount = (offer.quantity - details.filled) * offer.amount;
            _refundPayment(details.paymentToken, remainingAmount, offer.offerer);

            emit OfferCancelled(offerId, msg.sender, reason);
            return;
        }

        revert NFTExchange__InvalidListing();
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Get offers by offerer
     * @param offerer Address of the offerer
     * @param offerType Type of offers to retrieve
     * @return offerIds Array of offer IDs
     */
    function getOffersByOfferer(address offerer, OfferType offerType) external view returns (bytes32[] memory) {
        bytes32[] memory userOfferIds = userOffers[offerer];
        bytes32[] memory filteredOffers = new bytes32[](userOfferIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userOfferIds.length; i++) {
            bytes32 offerId = userOfferIds[i];

            if (offerType == OfferType.NFT_OFFER && nftOffers[offerId].offerId != bytes32(0)) {
                filteredOffers[count] = offerId;
                count++;
            } else if (offerType == OfferType.COLLECTION_OFFER && collectionOffers[offerId].offerId != bytes32(0)) {
                filteredOffers[count] = offerId;
                count++;
            } else if (offerType == OfferType.TRAIT_OFFER && traitOffers[offerId].offerId != bytes32(0)) {
                filteredOffers[count] = offerId;
                count++;
            }
        }

        // Resize array to actual count
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = filteredOffers[i];
        }
        return result;
    }

    /**
     * @notice Get offers by collection
     * @param collection Address of the collection
     * @param offerType Type of offers to retrieve
     * @return offerIds Array of offer IDs
     */
    function getOffersByCollection(address collection, OfferType offerType) external view returns (bytes32[] memory) {
        if (offerType == OfferType.NFT_OFFER) {
            // GAS OPTIMIZED: Use EnumerableSet to only iterate actual token IDs with offers
            EnumerableSet.UintSet storage tokenIds = _collectionTokenIds[collection];
            uint256 tokenCount = tokenIds.length();

            // Estimate max offers (could be multiple offers per token)
            uint256 maxOffers = tokenCount * 10; // Conservative estimate
            bytes32[] memory tempOffers = new bytes32[](maxOffers);
            uint256 count = 0;

            // Iterate only through token IDs that have offers
            for (uint256 i = 0; i < tokenCount; i++) {
                uint256 tokenId = tokenIds.at(i);
                bytes32[] memory tokenOffers = nftOfferIds[collection][tokenId];

                for (uint256 j = 0; j < tokenOffers.length; j++) {
                    bytes32 offerId = tokenOffers[j];
                    if (nftOffers[offerId].offerId != bytes32(0) && count < maxOffers) {
                        tempOffers[count] = offerId;
                        count++;
                    }
                }
            }

            // Resize array to actual count
            bytes32[] memory result = new bytes32[](count);
            for (uint256 i = 0; i < count; i++) {
                result[i] = tempOffers[i];
            }
            return result;
        } else if (offerType == OfferType.COLLECTION_OFFER) {
            // For collection offers, use the collectionOfferIds mapping
            bytes32[] memory collectionOfferList = collectionOfferIds[collection];
            uint256 maxCount = collectionOfferList.length;
            bytes32[] memory tempOffers = new bytes32[](maxCount);
            uint256 count = 0;

            for (uint256 i = 0; i < maxCount; i++) {
                bytes32 offerId = collectionOfferList[i];
                if (collectionOffers[offerId].offerId != bytes32(0)) {
                    tempOffers[count] = offerId;
                    count++;
                }
            }

            // Resize array to actual count
            bytes32[] memory result = new bytes32[](count);
            for (uint256 i = 0; i < count; i++) {
                result[i] = tempOffers[i];
            }
            return result;
        }

        // Return empty array for unsupported offer types
        return new bytes32[](0);
    }

    /**
     * @notice Get all active offers of a specific type
     * @param offerType Type of offers to retrieve
     * @return offerIds Array of active offer IDs
     */
    function getActiveOffers(OfferType offerType) external view returns (bytes32[] memory) {
        if (offerType == OfferType.NFT_OFFER) {
            return _getActiveNFTOffers();
        } else if (offerType == OfferType.COLLECTION_OFFER) {
            return _getActiveCollectionOffers();
        } else if (offerType == OfferType.TRAIT_OFFER) {
            return _getActiveTraitOffers();
        }

        // Return empty array for unknown types
        return new bytes32[](0);
    }

    /**
     * @notice Get active NFT offers
     */
    function _getActiveNFTOffers() internal view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](activeNFTOffers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < activeNFTOffers.length; i++) {
            bytes32 offerId = activeNFTOffers[i];
            if (nftOffers[offerId].status == OfferStatus.ACTIVE) {
                result[count] = offerId;
                count++;
            }
        }

        // Resize array to actual count
        bytes32[] memory activeOffers = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            activeOffers[i] = result[i];
        }
        return activeOffers;
    }

    /**
     * @notice Get active collection offers
     */
    function _getActiveCollectionOffers() internal view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](activeCollectionOffers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < activeCollectionOffers.length; i++) {
            bytes32 offerId = activeCollectionOffers[i];
            if (collectionOffers[offerId].status == OfferStatus.ACTIVE) {
                result[count] = offerId;
                count++;
            }
        }

        // Resize array to actual count
        bytes32[] memory activeOffers = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            activeOffers[i] = result[i];
        }
        return activeOffers;
    }

    /**
     * @notice Get active trait offers
     */
    function _getActiveTraitOffers() internal view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](activeTraitOffers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < activeTraitOffers.length; i++) {
            bytes32 offerId = activeTraitOffers[i];
            if (traitOffers[offerId].status == OfferStatus.ACTIVE) {
                result[count] = offerId;
                count++;
            }
        }

        // Resize array to actual count
        bytes32[] memory activeOffers = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            activeOffers[i] = result[i];
        }
        return activeOffers;
    }

    /**
     * @notice Remove offer from active tracking arrays
     * @param offerId Offer ID to remove
     * @param offerType Type of offer
     */
    function _removeFromActiveOffers(bytes32 offerId, OfferType offerType) internal {
        if (offerType == OfferType.NFT_OFFER) {
            _removeFromArray(activeNFTOffers, offerId);
        } else if (offerType == OfferType.COLLECTION_OFFER) {
            _removeFromArray(activeCollectionOffers, offerId);
        } else if (offerType == OfferType.TRAIT_OFFER) {
            _removeFromArray(activeTraitOffers, offerId);
        }
        delete activeOfferIndex[offerId];
    }

    /**
     * @notice Remove element from array by swapping with last element
     * @param array Array to modify
     * @param offerId Element to remove
     */
    function _removeFromArray(bytes32[] storage array, bytes32 offerId) internal {
        uint256 index = activeOfferIndex[offerId];
        if (index < array.length && array[index] == offerId) {
            // Move the last element to the deleted spot
            array[index] = array[array.length - 1];
            // Update the index mapping for the moved element
            if (array.length > 1) {
                activeOfferIndex[array[index]] = index;
            }
            // Remove the last element
            array.pop();
        }
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Pauses the contract (emergency function)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Generates unique offer ID
     */
    function _generateOfferId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender, offerCounter++));
    }

    /**
     * @notice Transfers NFT from seller to buyer using NFTTransferLib
     */
    function _transferNFT(address collection, uint256 tokenId, address from, address to) internal {
        // Create transfer parameters (amount=1 for single NFT offers)
        NFTTransferLib.TransferParams memory params = NFTTransferLib.createTransferParams(
            collection,
            tokenId,
            1, // Single NFT offer
            from,
            to
        );

        // Execute transfer using library
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        if (!result.success) {
            revert NFTExchange__TransferToSellerFailed();
        }
    }

    /**
     * @notice Processes payment with fees
     */
    function _processPayment(
        address collection,
        uint256 tokenId,
        uint256 amount,
        address paymentToken,
        address payer,
        address recipient
    ) internal returns (uint256 netAmount) {
        // Calculate fees using fee manager
        (uint256 platformFee, uint256 appliedDiscount) = feeManager.calculateFees(
            payer,
            collection,
            amount,
            false // isMaker = false for offer acceptance (buyer pays taker fee)
        );

        // For now, set royaltyFee to 0 as we're only handling platform fees
        uint256 royaltyFee = 0;

        netAmount = amount - platformFee - royaltyFee;

        // Transfer payment
        if (paymentToken == address(0)) {
            // ETH payment - use PaymentDistributionLib
            PaymentDistributionLib.PaymentData memory paymentData = PaymentDistributionLib.PaymentData({
                seller: recipient,
                royaltyReceiver: address(0), // No royalty for now
                marketplaceWallet: feeManager.feeRecipient(),
                totalAmount: amount,
                sellerAmount: netAmount,
                marketplaceFee: platformFee,
                royaltyAmount: royaltyFee
            });
            PaymentDistributionLib.distributePayment(paymentData);
        } else {
            // ERC20 payment
            IERC20(paymentToken).safeTransfer(recipient, netAmount);
            if (platformFee > 0) {
                IERC20(paymentToken).safeTransfer(feeManager.feeRecipient(), platformFee);
            }
        }

        return netAmount;
    }

    /**
     * @notice Refunds payment to offerer
     */
    function _refundPayment(address paymentToken, uint256 amount, address recipient) internal {
        if (paymentToken == address(0)) {
            // ETH refund
            payable(recipient).transfer(amount);
        } else {
            // ERC20 refund
            IERC20(paymentToken).safeTransfer(recipient, amount);
        }
    }
}
