// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/core/fees/AdvancedFeeManager.sol";
import "src/errors/NFTExchangeErrors.sol";
import "src/events/NFTExchangeEvents.sol";
import "src/libraries/NFTTransferLib.sol";
import "src/libraries/NFTValidationLib.sol";

/**
 * @title BundleManager
 * @notice Manages multi-NFT bundle creation and sales
 * @dev Supports bundles with mixed ERC721 and ERC1155 tokens
 * @author NFT Marketplace Team
 */
contract BundleManager is Ownable, ReentrancyGuard, Pausable, IERC1155Receiver, ERC165 {
    using SafeERC20 for IERC20;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Access control contract
    MarketplaceAccessControl public accessControl;

    /// @notice Fee manager contract
    AdvancedFeeManager public feeManager;

    /// @notice Bundle listings
    mapping(bytes32 => Bundle) public bundles;
    mapping(bytes32 => BundleTiming) public bundleTiming;
    mapping(bytes32 => BundleMetadata) public bundleMetadata;
    mapping(bytes32 => BundleItem[]) public bundleItems;

    /// @notice User's active bundles
    mapping(address => bytes32[]) public userBundles;

    /// @notice Array of all bundle IDs for pagination
    bytes32[] public allBundles;

    /// @notice Bundle counter for unique IDs
    uint256 public bundleCounter;

    /// @notice Total bundles created
    uint256 public totalBundlesCreated;

    /// @notice Total bundles sold
    uint256 public totalBundlesSold;

    /// @notice Maximum NFTs per bundle
    uint256 public constant MAX_NFTS_PER_BUNDLE = 20;

    /// @notice Minimum bundle duration (1 hour)
    uint256 public constant MIN_BUNDLE_DURATION = 1 hours;

    /// @notice Maximum bundle duration (30 days)
    uint256 public constant MAX_BUNDLE_DURATION = 30 days;

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice NFT item in a bundle
     */
    struct BundleItem {
        address collection; // NFT collection address
        uint256 tokenId; // Token ID
        uint256 amount; // Amount (for ERC1155, 1 for ERC721)
        TokenType tokenType; // ERC721 or ERC1155
        bool isIncluded; // Whether item is still in bundle
    }

    /**
     * @notice Bundle listing - Core data only
     */
    struct Bundle {
        bytes32 bundleId; // Unique bundle identifier
        address seller; // Bundle creator/seller
        uint256 totalPrice; // Total bundle price
        uint256 discountPercentage; // Discount from individual prices
        address paymentToken; // Payment token (ETH = address(0))
        BundleStatus status; // Current bundle status
    }

    /**
     * @notice Bundle timing information
     */
    struct BundleTiming {
        uint256 startTime; // Bundle start time
        uint256 endTime; // Bundle expiration time
        uint256 createdAt; // Creation timestamp
        uint256 soldAt; // Sale timestamp (if sold)
    }

    /**
     * @notice Bundle metadata
     */
    struct BundleMetadata {
        address buyer; // Buyer address (if sold)
        string description; // Bundle description
        string imageUrl; // Bundle image URL
    }

    /**
     * @notice Bundle pricing information
     */
    struct BundlePricing {
        uint256 totalIndividualPrice; // Sum of individual NFT prices
        uint256 bundlePrice; // Actual bundle price
        uint256 discountAmount; // Discount amount
        uint256 discountPercentage; // Discount percentage
        uint256 platformFee; // Platform fee
        uint256 totalRoyalties; // Total royalties
        uint256 netSellerAmount; // Net amount to seller
    }

    /**
     * @notice Token type enumeration
     */
    enum TokenType {
        ERC721,
        ERC1155
    }

    /**
     * @notice Bundle status enumeration
     */
    enum BundleStatus {
        ACTIVE,
        SOLD,
        CANCELLED,
        EXPIRED
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event BundleCreated(
        bytes32 indexed bundleId,
        address indexed seller,
        uint256 itemCount,
        uint256 totalPrice,
        uint256 discountPercentage
    );

    event BundleSold(
        bytes32 indexed bundleId, address indexed buyer, address indexed seller, uint256 totalPrice, uint256 itemCount
    );

    event BundleCancelled(bytes32 indexed bundleId, address indexed seller, string reason);

    event BundleUpdated(
        bytes32 indexed bundleId, address indexed seller, uint256 oldPrice, uint256 newPrice, uint256 timestamp
    );

    event BundleItemRemoved(bytes32 indexed bundleId, address indexed collection, uint256 tokenId);

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures caller has required role
     */
    modifier onlyRole(bytes32 role) {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert NFTExchange__NotTheOwner();
        }
        _;
    }

    /**
     * @notice Validates bundle parameters
     */
    modifier validBundleParams(BundleItem[] calldata items, uint256 totalPrice, uint256 endTime) {
        if (items.length == 0 || items.length > MAX_NFTS_PER_BUNDLE) {
            revert NFTExchange__AmountMustBeGreaterThanZero();
        }
        if (totalPrice == 0) {
            revert NFTExchange__PriceMustBeGreaterThanZero();
        }
        if (endTime <= block.timestamp + MIN_BUNDLE_DURATION || endTime > block.timestamp + MAX_BUNDLE_DURATION) {
            revert NFTExchange__DurationMustBeGreaterThanZero();
        }
        _;
    }

    /**
     * @notice Ensures bundle exists and is active
     */
    modifier bundleExists(bytes32 bundleId) {
        if (bundles[bundleId].bundleId == bytes32(0)) {
            revert NFTExchange__NFTNotActive();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the BundleManager
     * @param _accessControl Address of the access control contract
     * @param _feeManager Address of the fee manager contract
     */
    constructor(address _accessControl, address _feeManager) Ownable(msg.sender) {
        if (_accessControl == address(0) || _feeManager == address(0)) {
            revert NFTExchange__NotTheOwner();
        }

        accessControl = MarketplaceAccessControl(_accessControl);
        feeManager = AdvancedFeeManager(_feeManager);
        bundleCounter = 1;
    }

    // ============================================================================
    // BUNDLE CREATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a new NFT bundle
     * @param items Array of NFT items to include
     * @param totalPrice Total bundle price
     * @param discountPercentage Discount percentage from individual prices
     * @param paymentToken Payment token address (address(0) for ETH)
     * @param endTime Bundle expiration timestamp
     * @param description Bundle description
     * @param imageUrl Bundle image URL
     * @return bundleId Unique bundle identifier
     */
    function createBundle(
        BundleItem[] calldata items,
        uint256 totalPrice,
        uint256 discountPercentage,
        address paymentToken,
        uint256 endTime,
        string calldata description,
        string calldata imageUrl
    ) external nonReentrant whenNotPaused validBundleParams(items, totalPrice, endTime) returns (bytes32) {
        if (discountPercentage > 5000) {
            // Max 50% discount
            revert NFTExchange__PriceMustBeGreaterThanZero();
        }

        return
            _createBundleInternal(items, totalPrice, discountPercentage, paymentToken, endTime, description, imageUrl);
    }

    /**
     * @notice Purchases a bundle
     * @param bundleId Bundle identifier
     */
    function purchaseBundle(bytes32 bundleId) external payable nonReentrant whenNotPaused bundleExists(bundleId) {
        Bundle storage bundle = bundles[bundleId];

        if (bundle.status != BundleStatus.ACTIVE) {
            revert NFTExchange__NFTNotActive();
        }

        BundleTiming storage timing = bundleTiming[bundleId];
        if (block.timestamp > timing.endTime) {
            bundle.status = BundleStatus.EXPIRED;
            revert NFTExchange__ListingExpired();
        }

        if (bundle.seller == msg.sender) {
            revert NFTExchange__NotTheOwner();
        }

        // Handle payment
        if (bundle.paymentToken == address(0)) {
            // ETH payment
            if (msg.value != bundle.totalPrice) {
                revert NFTExchange__InsufficientPayment();
            }
        } else {
            // ERC20 payment
            IERC20(bundle.paymentToken).safeTransferFrom(msg.sender, address(this), bundle.totalPrice);
        }

        // Calculate and distribute fees
        BundlePricing memory pricing = _calculateBundlePricing(bundle);
        _distributeBundlePayment(bundle, pricing, msg.sender);

        // Transfer all NFTs to buyer
        BundleItem[] storage items = bundleItems[bundleId];
        for (uint256 i = 0; i < items.length; i++) {
            if (items[i].isIncluded) {
                _transferNFTFromEscrow(items[i], msg.sender);
            }
        }

        // Update bundle status
        bundle.status = BundleStatus.SOLD;
        timing.soldAt = block.timestamp;
        BundleMetadata storage metadata = bundleMetadata[bundleId];
        metadata.buyer = msg.sender;

        totalBundlesSold++;

        emit BundleSold(bundleId, msg.sender, bundle.seller, bundle.totalPrice, items.length);
    }

    /**
     * @notice Cancels a bundle listing
     * @param bundleId Bundle identifier
     * @param reason Cancellation reason
     */
    function cancelBundle(bytes32 bundleId, string calldata reason) external nonReentrant bundleExists(bundleId) {
        Bundle storage bundle = bundles[bundleId];

        if (bundle.seller != msg.sender) {
            revert NFTExchange__NotTheOwner();
        }

        if (bundle.status != BundleStatus.ACTIVE) {
            revert NFTExchange__NFTNotActive();
        }

        // Return all NFTs to seller
        BundleItem[] storage items = bundleItems[bundleId];
        for (uint256 i = 0; i < items.length; i++) {
            if (items[i].isIncluded) {
                _transferNFTFromEscrow(items[i], bundle.seller);
            }
        }

        bundle.status = BundleStatus.CANCELLED;

        emit BundleCancelled(bundleId, msg.sender, reason);
    }

    /**
     * @notice Gets basic bundle information
     * @param bundleId Bundle identifier
     * @return bundleId Bundle ID
     * @return seller Bundle seller
     * @return totalPrice Total bundle price
     * @return discountPercentage Discount percentage
     * @return paymentToken Payment token address
     * @return status Bundle status
     */
    function getBundleBasicInfo(bytes32 bundleId)
        external
        view
        bundleExists(bundleId)
        returns (bytes32, address, uint256, uint256, address, BundleStatus)
    {
        Bundle storage bundle = bundles[bundleId];
        return (
            bundle.bundleId,
            bundle.seller,
            bundle.totalPrice,
            bundle.discountPercentage,
            bundle.paymentToken,
            bundle.status
        );
    }

    /**
     * @notice Gets bundle timing information
     * @param bundleId Bundle identifier
     * @return startTime Bundle start time
     * @return endTime Bundle end time
     * @return createdAt Creation timestamp
     * @return soldAt Sale timestamp
     */
    function getBundleTimingInfo(bytes32 bundleId)
        external
        view
        bundleExists(bundleId)
        returns (uint256, uint256, uint256, uint256)
    {
        BundleTiming storage timing = bundleTiming[bundleId];
        return (timing.startTime, timing.endTime, timing.createdAt, timing.soldAt);
    }

    /**
     * @notice Gets bundle metadata
     * @param bundleId Bundle identifier
     * @return buyer Buyer address
     * @return description Bundle description
     * @return imageUrl Bundle image URL
     */
    function getBundleMetadata(bytes32 bundleId)
        external
        view
        bundleExists(bundleId)
        returns (address, string memory, string memory)
    {
        BundleMetadata storage metadata = bundleMetadata[bundleId];
        return (metadata.buyer, metadata.description, metadata.imageUrl);
    }

    /**
     * @notice Gets bundle status
     * @param bundleId Bundle identifier
     * @return Bundle status
     */
    function getBundleStatus(bytes32 bundleId) external view bundleExists(bundleId) returns (BundleStatus) {
        return bundles[bundleId].status;
    }

    /**
     * @notice Gets bundle seller
     * @param bundleId Bundle identifier
     * @return Bundle seller address
     */
    function getBundleSeller(bytes32 bundleId) external view bundleExists(bundleId) returns (address) {
        return bundles[bundleId].seller;
    }

    /**
     * @notice Gets bundle price
     * @param bundleId Bundle identifier
     * @return Bundle total price
     */
    function getBundlePrice(bytes32 bundleId) external view bundleExists(bundleId) returns (uint256) {
        return bundles[bundleId].totalPrice;
    }

    /**
     * @notice Updates bundle price
     * @param bundleId Bundle identifier
     * @param newPrice New bundle price
     */
    function updateBundlePrice(bytes32 bundleId, uint256 newPrice) external nonReentrant bundleExists(bundleId) {
        Bundle storage bundle = bundles[bundleId];

        if (bundle.seller != msg.sender) {
            revert NFTExchange__NotTheOwner();
        }

        if (bundle.status != BundleStatus.ACTIVE) {
            revert NFTExchange__NFTNotActive();
        }

        if (newPrice == 0) {
            revert NFTExchange__PriceMustBeGreaterThanZero();
        }

        uint256 oldPrice = bundle.totalPrice;
        bundle.totalPrice = newPrice;

        emit BundleUpdated(bundleId, msg.sender, oldPrice, newPrice, block.timestamp);
    }

    /**
     * @notice Gets user's bundles
     * @param user User address
     * @return Array of bundle IDs
     */
    function getUserBundles(address user) external view returns (bytes32[] memory) {
        return userBundles[user];
    }

    /**
     * @notice Gets active bundles with pagination
     * @param offset Starting index
     * @param limit Maximum number of bundles to return
     * @return Array of active bundle IDs
     */
    function getActiveBundles(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        uint256 activeCount = 0;

        // First pass: count active bundles
        for (uint256 i = 0; i < allBundles.length; i++) {
            if (bundles[allBundles[i]].status == BundleStatus.ACTIVE) {
                activeCount++;
            }
        }

        if (activeCount == 0 || offset >= activeCount) {
            return new bytes32[](0);
        }

        // Calculate actual return size
        uint256 returnSize = activeCount - offset;
        if (returnSize > limit) {
            returnSize = limit;
        }

        bytes32[] memory activeBundles = new bytes32[](returnSize);
        uint256 currentIndex = 0;
        uint256 returnIndex = 0;

        // Second pass: collect active bundles with pagination
        for (uint256 i = 0; i < allBundles.length && returnIndex < returnSize; i++) {
            if (bundles[allBundles[i]].status == BundleStatus.ACTIVE) {
                if (currentIndex >= offset) {
                    activeBundles[returnIndex] = allBundles[i];
                    returnIndex++;
                }
                currentIndex++;
            }
        }

        return activeBundles;
    }

    /**
     * @notice Pauses the contract (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Generates unique bundle ID
     */
    function _generateBundleId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender, bundleCounter++));
    }

    /**
     * @notice Internal function to create bundle
     */
    function _createBundleInternal(
        BundleItem[] calldata items,
        uint256 totalPrice,
        uint256 discountPercentage,
        address paymentToken,
        uint256 endTime,
        string calldata description,
        string calldata imageUrl
    ) internal returns (bytes32 bundleId) {
        bundleId = _generateBundleId();

        // Validate ownership and transfer NFTs to escrow
        _escrowBundleItems(items);

        // Create and configure bundle
        _createBundleStorage(bundleId, items.length, totalPrice, discountPercentage);
        _configureBundleDetails(bundleId, paymentToken, endTime, description, imageUrl);
        _addItemsToBundle(bundleId, items);

        return bundleId;
    }

    /**
     * @notice Escrows all items in a bundle
     */
    function _escrowBundleItems(BundleItem[] calldata items) internal {
        for (uint256 i = 0; i < items.length; i++) {
            _validateAndEscrowNFT(items[i], msg.sender);
        }
    }

    /**
     * @notice Creates basic bundle storage
     */
    function _createBundleStorage(bytes32 bundleId, uint256 itemCount, uint256 totalPrice, uint256 discountPercentage)
        internal
    {
        Bundle storage bundle = bundles[bundleId];
        bundle.bundleId = bundleId;
        bundle.seller = msg.sender;
        bundle.totalPrice = totalPrice;
        bundle.discountPercentage = discountPercentage;
        bundle.status = BundleStatus.ACTIVE;

        BundleTiming storage timing = bundleTiming[bundleId];
        timing.createdAt = block.timestamp;
        timing.startTime = block.timestamp;

        // Update mappings
        userBundles[msg.sender].push(bundleId);
        allBundles.push(bundleId);
        totalBundlesCreated++;

        emit BundleCreated(bundleId, msg.sender, itemCount, totalPrice, discountPercentage);
    }

    /**
     * @notice Configures bundle details
     */
    function _configureBundleDetails(
        bytes32 bundleId,
        address paymentToken,
        uint256 endTime,
        string calldata description,
        string calldata imageUrl
    ) internal {
        Bundle storage bundle = bundles[bundleId];
        bundle.paymentToken = paymentToken;

        BundleTiming storage timing = bundleTiming[bundleId];
        timing.endTime = endTime;

        BundleMetadata storage metadata = bundleMetadata[bundleId];
        metadata.description = description;
        metadata.imageUrl = imageUrl;
    }

    /**
     * @notice Adds items to bundle
     */
    function _addItemsToBundle(bytes32 bundleId, BundleItem[] calldata items) internal {
        for (uint256 i = 0; i < items.length; i++) {
            bundleItems[bundleId].push(items[i]);
        }
    }

    /**
     * @notice Validates ownership and escrows NFT using NFTTransferLib
     */
    function _validateAndEscrowNFT(BundleItem calldata item, address owner) internal {
        if (item.tokenType == TokenType.ERC721) {
            IERC721 nft = IERC721(item.collection);
            if (nft.ownerOf(item.tokenId) != owner) {
                revert NFTExchange__NotTheOwner();
            }
        } else {
            IERC1155 nft = IERC1155(item.collection);
            if (nft.balanceOf(owner, item.tokenId) < item.amount) {
                revert NFTExchange__InsufficientBalance();
            }
        }

        // Transfer to escrow using library
        NFTTransferLib.TransferParams memory params =
            NFTTransferLib.createTransferParams(item.collection, item.tokenId, item.amount, owner, address(this));

        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);
        if (!result.success) {
            revert NFTExchange__TransferToSellerFailed();
        }
    }

    /**
     * @notice Transfers NFT from escrow to recipient using NFTTransferLib
     */
    function _transferNFTFromEscrow(BundleItem memory item, address recipient) internal {
        // Transfer from escrow using library
        NFTTransferLib.TransferParams memory params =
            NFTTransferLib.createTransferParams(item.collection, item.tokenId, item.amount, address(this), recipient);

        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);
        if (!result.success) {
            revert NFTExchange__TransferToSellerFailed();
        }
    }

    /**
     * @notice Calculates bundle pricing with fees
     */
    function _calculateBundlePricing(Bundle memory bundle) internal view returns (BundlePricing memory pricing) {
        // For simplicity, we'll calculate a flat platform fee
        // In practice, you'd integrate with your fee manager
        pricing.bundlePrice = bundle.totalPrice;
        pricing.platformFee = (bundle.totalPrice * 250) / 10000; // 2.5%
        pricing.totalRoyalties = 0; // Would calculate per NFT
        pricing.netSellerAmount = bundle.totalPrice - pricing.platformFee - pricing.totalRoyalties;

        return pricing;
    }

    /**
     * @notice Distributes bundle payment
     */
    function _distributeBundlePayment(Bundle memory bundle, BundlePricing memory pricing, address buyer) internal {
        if (bundle.paymentToken == address(0)) {
            // ETH payment
            payable(bundle.seller).transfer(pricing.netSellerAmount);
            if (pricing.platformFee > 0) {
                payable(feeManager.feeRecipient()).transfer(pricing.platformFee);
            }
        } else {
            // ERC20 payment
            IERC20(bundle.paymentToken).safeTransfer(bundle.seller, pricing.netSellerAmount);
            if (pricing.platformFee > 0) {
                IERC20(bundle.paymentToken).safeTransfer(feeManager.feeRecipient(), pricing.platformFee);
            }
        }
    }

    // ============================================================================
    // IERC1155RECEIVER IMPLEMENTATION
    // ============================================================================

    /**
     * @notice Handles the receipt of a single ERC1155 token type
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @notice Handles the receipt of multiple ERC1155 token types
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /**
     * @notice Returns true if this contract implements the interface defined by interfaceId
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
