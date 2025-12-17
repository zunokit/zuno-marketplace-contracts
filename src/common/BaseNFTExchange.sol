// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "src/errors/NFTExchangeErrors.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import {Fee} from "src/common/Fee.sol";
import "src/events/NFTExchangeEvents.sol";
import {IExchangeCore} from "src/interfaces/IMarketplaceCore.sol";
import {PaymentDistributionLib} from "src/libraries/PaymentDistributionLib.sol";
import {RoyaltyLib} from "src/libraries/RoyaltyLib.sol";
import {ArrayUtilsLib} from "src/libraries/ArrayUtilsLib.sol";
import {GasOptimizedLibrary} from "src/optimizations/GasOptimizedLibrary.sol";

contract BaseNFTExchange is Initializable, Ownable, ReentrancyGuard, ERC165, IExchangeCore {
    struct Listing {
        address contractAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
        uint256 listingDuration;
        uint256 listingStart;
        ListingStatus status;
        uint256 amount;
    }
    // Enum for listing status

    enum ListingStatus {
        Pending,
        Active,
        Sold,
        Failed,
        Cancelled,
        Expired
    }

    // Constants
    uint256 public s_takerFee = 200; // 2% taker fee in basis points (updatable)
    uint256 public constant BPS_DENOMINATOR = 10000; // Basis points denominator

    // Storage variables
    mapping(bytes32 => Listing) public s_listings; // Maps listingId to Listing
    mapping(address => bytes32[]) public s_listingsByCollection; // Maps contract address to listing IDs
    mapping(address => bytes32[]) public s_listingsBySeller; // Maps seller address to listing IDs

    // Track active listings for each NFT to prevent duplicate listings
    // contractAddress => tokenId => seller => listingId
    mapping(address => mapping(uint256 => mapping(address => bytes32))) public s_activeListings;

    address public s_marketplaceWallet; // Wallet for taker fees

    // Events

    /**
     * @notice Constructor for BaseNFTExchange
     * @dev Sets up the contract for initialization
     */
    constructor() Ownable(msg.sender) {
        // Constructor is empty to allow initialization
    }

    /**
     * @notice Initializes the BaseNFTExchange contract
     * @param m_marketplaceWallet The marketplace wallet address
     * @param m_owner The owner of the contract
     */
    function __BaseNFTExchange_init(address m_marketplaceWallet, address m_owner) internal onlyInitializing {
        if (m_marketplaceWallet == address(0)) {
            revert NFTExchange__InvalidMarketplaceWallet();
        }
        if (m_owner == address(0)) {
            revert NFTExchange__InvalidMarketplaceWallet(); // Reusing error for zero address
        }

        // Initialize Ownable
        _transferOwnership(m_owner);

        // Set marketplace wallet
        s_marketplaceWallet = m_marketplaceWallet;
    }

    /**
     * @notice Updates the marketplace wallet address
     * @param m_newMarketplaceWallet The new marketplace wallet address
     */
    function updateMarketplaceWallet(address m_newMarketplaceWallet) external onlyOwner {
        if (m_newMarketplaceWallet == address(0)) {
            revert NFTExchange__InvalidMarketplaceWallet();
        }
        address oldWallet = s_marketplaceWallet;
        s_marketplaceWallet = m_newMarketplaceWallet;
        emit MarketplaceWalletUpdated(oldWallet, m_newMarketplaceWallet);
    }

    /**
     * @notice Updates the taker fee
     * @param m_newTakerFee The new taker fee in basis points
     */
    function updateTakerFee(uint256 m_newTakerFee) external onlyOwner {
        if (m_newTakerFee > BPS_DENOMINATOR) {
            revert NFTExchange__InvalidTakerFee();
        }
        uint256 oldFee = s_takerFee;
        s_takerFee = m_newTakerFee;
        emit TakerFeeUpdated(oldFee, m_newTakerFee);
    }

    // Modifier to check active listing
    modifier onlyActiveListing(bytes32 m_listingId) {
        if (s_listings[m_listingId].status != ListingStatus.Active) {
            revert NFTExchange__NFTNotActive();
        }
        if (block.timestamp >= s_listings[m_listingId].listingStart + s_listings[m_listingId].listingDuration) {
            revert NFTExchange__ListingExpired();
        }
        _;
    }

    // Internal function to remove listing from array
    function _removeListingFromArray(bytes32[] storage s_array, bytes32 m_listingId) internal {
        ArrayUtilsLib.removeBytes32Element(s_array, m_listingId);
    }

    // Internal function to generate listing ID
    function _generateListingId(address m_contractAddress, uint256 m_tokenId, address m_sender)
        internal
        view
        returns (bytes32)
    {
        // Use gas-optimized assembly version for listing ID generation
        return GasOptimizedLibrary.generateOptimizedListingId(m_contractAddress, m_tokenId, m_sender, block.timestamp);
    }

    // Internal function to create a single listing
    function _createListing(
        address m_contractAddress,
        uint256 m_tokenId,
        uint256 m_price,
        uint256 m_listingDuration,
        uint256 m_amount,
        bytes32 m_listingId
    ) internal {
        // Check if NFT is already listed by this seller
        bytes32 existingListingId = s_activeListings[m_contractAddress][m_tokenId][msg.sender];
        if (existingListingId != bytes32(0)) {
            // Check if existing listing is still active
            Listing storage existingListing = s_listings[existingListingId];
            if (
                existingListing.status == ListingStatus.Active
                    && block.timestamp < existingListing.listingStart + existingListing.listingDuration
            ) {
                revert NFTExchange__NFTAlreadyListed();
            }
        }

        s_listings[m_listingId] = Listing({
            contractAddress: m_contractAddress,
            tokenId: m_tokenId,
            price: m_price,
            seller: msg.sender,
            listingDuration: m_listingDuration,
            listingStart: block.timestamp,
            status: ListingStatus.Active,
            amount: m_amount
        });

        s_listingsByCollection[m_contractAddress].push(m_listingId);
        s_listingsBySeller[msg.sender].push(m_listingId);

        // Track this active listing
        s_activeListings[m_contractAddress][m_tokenId][msg.sender] = m_listingId;

        emit NFTListed(m_listingId, m_contractAddress, m_tokenId, msg.sender, m_price);
    }

    // Struct to reduce stack depth in payment distribution
    struct PaymentDistribution {
        address seller;
        address royaltyReceiver;
        uint256 price;
        uint256 royalty;
        uint256 takerFee;
        uint256 realityPrice;
    }

    // Internal function to distribute payments
    function _distributePayments(PaymentDistribution memory payment) internal {
        // Calculate seller amount (listing price minus royalty)
        uint256 sellerAmount = payment.price - payment.royalty;

        // Convert to PaymentDistributionLib format
        PaymentDistributionLib.PaymentData memory paymentData = PaymentDistributionLib.PaymentData({
            seller: payment.seller,
            royaltyReceiver: payment.royaltyReceiver,
            marketplaceWallet: s_marketplaceWallet,
            totalAmount: sellerAmount + payment.takerFee + payment.royalty, // Sum of all payments
            sellerAmount: sellerAmount,
            marketplaceFee: payment.takerFee,
            royaltyAmount: payment.royalty
        });

        PaymentDistributionLib.distributePayment(paymentData);
    }

    // Internal function to distribute payments and emit event
    function _distributePaymentsWithEvent(bytes32 listingId, PaymentDistribution memory payment) internal {
        // Calculate seller amount (listing price minus royalty)
        uint256 sellerAmount = payment.price - payment.royalty;
        uint256 totalPrice = payment.price + payment.takerFee;

        // Distribute payments
        _distributePayments(payment);

        // Emit detailed payment distribution event
        emit PaymentDistributed(
            listingId,
            payment.seller,
            msg.sender,
            totalPrice,
            sellerAmount,
            payment.takerFee,
            payment.royalty,
            payment.royaltyReceiver
        );
    }

    // Internal function to finalize listing
    function _finalizeListing(bytes32 m_listingId, address m_contractAddress, address m_seller) internal {
        // Update listing status
        s_listings[m_listingId].status = ListingStatus.Sold;

        uint256 tokenId = s_listings[m_listingId].tokenId;

        // Remove from active listings
        delete s_activeListings[m_contractAddress][tokenId][m_seller];

        // Remove from collection and seller listings
        _removeListingFromArray(s_listingsByCollection[m_contractAddress], m_listingId);
        _removeListingFromArray(s_listingsBySeller[m_seller], m_listingId);

        // Emit event
        emit NFTSold(m_listingId, m_contractAddress, tokenId, m_seller, msg.sender, s_listings[m_listingId].price);
    }

    // View function to get floor price (placeholder, needs oracle)
    function getFloorPrice(address /* m_contractAddress */ ) public view virtual returns (uint256) {
        // Placeholder: Use an oracle (e.g., Chainlink) for real floor price
        return 1 ether; // Example: 1 ETH
    }

    // View function to get top trait price (placeholder, needs oracle)
    function getTopTraitPrice(address m_contractAddress, uint256 /* m_tokenId */ )
        public
        view
        virtual
        returns (uint256)
    {
        // Placeholder: Use oracle or off-chain data for trait-based pricing
        return (getFloorPrice(m_contractAddress) * 120) / 100; // Example: 20% above floor
    }

    // View function to get ladder price (placeholder, needs oracle)
    function getLadderPrice(address m_contractAddress, uint256 /* m_tokenId */ )
        public
        view
        virtual
        returns (uint256)
    {
        // Placeholder: Use a tiered pricing strategy from off-chain data
        return (getFloorPrice(m_contractAddress) * 110) / 100; // Example: 10% above floor
    }

    // View function to get royalty info
    function getRoyaltyInfo(address m_contractAddress, uint256 m_tokenId, uint256 m_salePrice)
        public
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        return RoyaltyLib.calculateRoyalty(m_contractAddress, m_tokenId, m_salePrice);
    }

    // View function to get buyer-sees price (reality price)
    function getBuyerSeesPrice(bytes32 m_listingId) public view returns (uint256) {
        Listing storage s_listing = s_listings[m_listingId];
        (, uint256 m_royalty) = getRoyaltyInfo(s_listing.contractAddress, s_listing.tokenId, s_listing.price);
        uint256 m_takerFee = (s_listing.price * s_takerFee) / BPS_DENOMINATOR;
        return s_listing.price + m_royalty + m_takerFee;
    }

    // View function to get floor difference
    function getFloorDiff(bytes32 m_listingId) public view returns (int256) {
        Listing storage s_listing = s_listings[m_listingId];
        uint256 m_floorPrice = getFloorPrice(s_listing.contractAddress);
        return int256(s_listing.price) - int256(m_floorPrice);
    }

    // View function to get 24-hour volume (placeholder, needs oracle)
    function get24hVolume(address /* m_contractAddress */ ) public view virtual returns (uint256) {
        // Placeholder: Use oracle or off-chain data for 24h trading volume
        return 10 ether; // Example: 10 ETH
    }

    // View function to get listings by collection
    function getListingsByCollection(address m_contractAddress) public view returns (bytes32[] memory) {
        return s_listingsByCollection[m_contractAddress];
    }

    // View function to get listings by seller
    function getListingsBySeller(address m_seller) public view returns (bytes32[] memory) {
        return s_listingsBySeller[m_seller];
    }

    function getGeneratedListingId(address m_contractAddress, uint256 m_tokenId, address m_sender)
        public
        view
        returns (bytes32)
    {
        return _generateListingId(m_contractAddress, m_tokenId, m_sender);
    }

    // Getter for taker fee
    function getTakerFee() external view returns (uint256) {
        return s_takerFee;
    }

    // ============ IMarketplaceCore Implementation ============

    /**
     * @notice Returns the version of the marketplace contract
     * @return version The version string
     */
    function version() public pure virtual override returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Returns the type of marketplace contract
     * @return contractType The contract type identifier
     */
    function contractType() public pure virtual override returns (string memory) {
        return "NFTExchange";
    }

    /**
     * @notice Returns whether this contract is active
     * @return active True if the contract is active
     */
    function isActive() public view virtual override returns (bool) {
        return true; // Base implementation always active
    }

    // ============ IExchangeCore Implementation ============

    /**
     * @notice Returns the supported NFT standard
     * @return standard The NFT standard (ERC721 or ERC1155)
     * @dev Must be overridden by child contracts
     */
    function supportedStandard() public pure virtual override returns (string memory) {
        return "UNKNOWN"; // Must be overridden
    }

    /**
     * @notice Returns the marketplace wallet address
     * @return wallet The marketplace wallet address
     */
    function marketplaceWallet() public view virtual override returns (address) {
        return s_marketplaceWallet;
    }

    // ============ ERC165 Implementation ============

    /**
     * @dev See {IERC165-supportsInterface}.
     * @notice Returns true if this contract implements the interface defined by interfaceId
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @return bool True if the contract implements interfaceId
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExchangeCore).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ============================================================================
    // GETTER FUNCTIONS FOR CLI/FRONTEND INTEGRATION
    // ============================================================================

    /**
     * @notice Get active listing ID for a specific NFT
     * @dev Returns zero bytes32 if no active listing exists
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param seller Seller address
     * @return listingId The listing ID if active, zero bytes32 otherwise
     */
    function getActiveListingByNFT(address nftContract, uint256 tokenId, address seller)
        external
        view
        returns (bytes32 listingId)
    {
        listingId = s_activeListings[nftContract][tokenId][seller];

        // Validate it's truly active and not expired
        if (listingId != bytes32(0)) {
            Listing storage listing = s_listings[listingId];
            if (
                listing.status != ListingStatus.Active
                    || block.timestamp >= listing.listingStart + listing.listingDuration
            ) {
                return bytes32(0);
            }
        }

        return listingId;
    }

    /**
     * @notice Get all active listings by seller
     * @param seller Seller address
     * @return activeListings Array of active listing IDs
     */
    function getActiveListingsBySeller(address seller) external view returns (bytes32[] memory activeListings) {
        bytes32[] memory allListings = s_listingsBySeller[seller];
        uint256 activeCount = 0;

        // First pass: count active listings
        for (uint256 i = 0; i < allListings.length; i++) {
            Listing storage listing = s_listings[allListings[i]];
            if (
                listing.status == ListingStatus.Active
                    && block.timestamp < listing.listingStart + listing.listingDuration
            ) {
                activeCount++;
            }
        }

        // Second pass: populate array
        activeListings = new bytes32[](activeCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allListings.length; i++) {
            Listing storage listing = s_listings[allListings[i]];
            if (
                listing.status == ListingStatus.Active
                    && block.timestamp < listing.listingStart + listing.listingDuration
            ) {
                activeListings[currentIndex] = allListings[i];
                currentIndex++;
            }
        }

        return activeListings;
    }

    /**
     * @notice Check if NFT is currently listed
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @return isListed True if actively listed by anyone
     * @return listingId The listing ID if listed, zero bytes32 otherwise
     * @return seller The seller address if listed
     */
    function isNFTListed(address nftContract, uint256 tokenId)
        external
        view
        returns (bool isListed, bytes32 listingId, address seller)
    {
        // Check all collection listings for this NFT
        bytes32[] memory collectionListings = s_listingsByCollection[nftContract];

        for (uint256 i = 0; i < collectionListings.length; i++) {
            Listing storage listing = s_listings[collectionListings[i]];

            if (
                listing.tokenId == tokenId && listing.status == ListingStatus.Active
                    && block.timestamp < listing.listingStart + listing.listingDuration
            ) {
                return (true, collectionListings[i], listing.seller);
            }
        }

        return (false, bytes32(0), address(0));
    }

    /**
     * @notice Get total active listings count for a collection
     * @param nftContract NFT contract address
     * @return count Number of active listings
     */
    function getActiveListingsCount(address nftContract) external view returns (uint256 count) {
        bytes32[] memory collectionListings = s_listingsByCollection[nftContract];

        for (uint256 i = 0; i < collectionListings.length; i++) {
            Listing storage listing = s_listings[collectionListings[i]];
            if (
                listing.status == ListingStatus.Active
                    && block.timestamp < listing.listingStart + listing.listingDuration
            ) {
                count++;
            }
        }

        return count;
    }

    /**
     * @notice Batch check if multiple NFTs are listed
     * @param nftContracts Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @return listed Array of boolean values indicating if each NFT is listed
     */
    function batchIsNFTListed(address[] calldata nftContracts, uint256[] calldata tokenIds)
        external
        view
        returns (bool[] memory listed)
    {
        require(nftContracts.length == tokenIds.length, "Array length mismatch");

        listed = new bool[](nftContracts.length);

        for (uint256 i = 0; i < nftContracts.length; i++) {
            bytes32 listingId = s_activeListings[nftContracts[i]][tokenIds[i]][msg.sender];

            if (listingId != bytes32(0)) {
                Listing storage listing = s_listings[listingId];
                listed[i] = listing.status == ListingStatus.Active
                    && block.timestamp < listing.listingStart + listing.listingDuration;
            } else {
                listed[i] = false;
            }
        }

        return listed;
    }

    // ============================================================================
    // EXPIRED LISTING CLEANUP FUNCTIONS
    // ============================================================================

    /**
     * @notice Check if a listing has expired based on time
     * @param listingId The listing ID to check
     * @return isExpired True if the listing duration has passed
     */
    function isListingExpired(bytes32 listingId) public view returns (bool isExpired) {
        Listing storage listing = s_listings[listingId];
        if (listing.status != ListingStatus.Active) {
            return false;
        }
        return block.timestamp >= listing.listingStart + listing.listingDuration;
    }

    /**
     * @notice Cleanup a single expired listing by updating its status
     * @dev Anyone can call this to help maintain contract state
     * @param listingId The listing ID to cleanup
     * @return cleaned True if the listing was cleaned up
     */
    function cleanupExpiredListing(bytes32 listingId) public returns (bool cleaned) {
        Listing storage listing = s_listings[listingId];

        // Only cleanup active listings that have expired
        if (listing.status != ListingStatus.Active) {
            return false;
        }

        uint256 expirationTime = listing.listingStart + listing.listingDuration;
        if (block.timestamp < expirationTime) {
            return false;
        }

        // Update status to Expired
        listing.status = ListingStatus.Expired;

        // Remove from arrays
        _removeListingFromArray(s_listingsByCollection[listing.contractAddress], listingId);
        _removeListingFromArray(s_listingsBySeller[listing.seller], listingId);

        // Remove from active listings mapping
        delete s_activeListings[listing.contractAddress][listing.tokenId][listing.seller];

        // Emit event
        emit ListingExpired(listingId, listing.contractAddress, listing.tokenId, listing.seller, expirationTime);

        return true;
    }

    /**
     * @notice Batch cleanup multiple expired listings
     * @dev Anyone can call this to help maintain contract state
     * @param listingIds Array of listing IDs to cleanup
     * @return cleanedCount Number of listings that were cleaned up
     */
    function batchCleanupExpiredListings(bytes32[] calldata listingIds) external returns (uint256 cleanedCount) {
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (cleanupExpiredListing(listingIds[i])) {
                cleanedCount++;
            }
        }
        return cleanedCount;
    }

    /**
     * @notice Get expired listing IDs for a seller (for cleanup purposes)
     * @param seller Seller address
     * @return expiredListings Array of expired listing IDs
     */
    function getExpiredListingsBySeller(address seller) external view returns (bytes32[] memory expiredListings) {
        bytes32[] memory allListings = s_listingsBySeller[seller];
        uint256 expiredCount = 0;

        // First pass: count expired listings
        for (uint256 i = 0; i < allListings.length; i++) {
            Listing storage listing = s_listings[allListings[i]];
            if (
                listing.status == ListingStatus.Active
                    && block.timestamp >= listing.listingStart + listing.listingDuration
            ) {
                expiredCount++;
            }
        }

        // Second pass: populate array
        expiredListings = new bytes32[](expiredCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allListings.length; i++) {
            Listing storage listing = s_listings[allListings[i]];
            if (
                listing.status == ListingStatus.Active
                    && block.timestamp >= listing.listingStart + listing.listingDuration
            ) {
                expiredListings[currentIndex] = allListings[i];
                currentIndex++;
            }
        }

        return expiredListings;
    }

    /**
     * @notice Get the real status of a listing (accounts for time-based expiration)
     * @param listingId The listing ID to check
     * @return status The real status (Expired if time has passed even if stored as Active)
     */
    function getRealListingStatus(bytes32 listingId) external view returns (ListingStatus status) {
        Listing storage listing = s_listings[listingId];

        // If stored status is Active but time has expired, return Expired
        if (listing.status == ListingStatus.Active) {
            if (block.timestamp >= listing.listingStart + listing.listingDuration) {
                return ListingStatus.Expired;
            }
        }

        return listing.status;
    }
}
