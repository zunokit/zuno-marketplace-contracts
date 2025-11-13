// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "src/types/ListingTypes.sol";
import "src/errors/AdvancedListingErrors.sol";
import "src/events/AdvancedListingEvents.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import "src/core/validation/MarketplaceValidator.sol";
import "src/libraries/NFTTransferLib.sol";
import "src/libraries/NFTValidationLib.sol";
import "src/libraries/PaymentDistributionLib.sol";

/**
 * @title AdvancedListingManager
 * @notice Manages advanced listing types for NFT marketplace
 * @dev Supports multiple listing types including fixed price, auctions, bundles, and offers
 * @author NFT Marketplace Team
 */
contract AdvancedListingManager is Ownable, ReentrancyGuard, Pausable {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Access control contract
    MarketplaceAccessControl public accessControl;

    /// @notice Marketplace validator contract
    MarketplaceValidator public validator;

    /// @notice Mapping from listing ID to listing data
    mapping(bytes32 => Listing) public listings;

    /// @notice Mapping from listing ID to auction parameters
    mapping(bytes32 => AuctionParams) public auctionParams;

    /// @notice Mapping from listing ID to Dutch auction parameters
    mapping(bytes32 => DutchAuctionParams) public dutchAuctionParams;

    /// @notice Mapping from offer ID to offer data
    mapping(bytes32 => Offer) public offers;

    /// @notice Mapping from bundle ID to bundle data
    mapping(bytes32 => Bundle) public bundles;

    /// @notice Mapping from user to their active listings
    mapping(address => bytes32[]) public userListings;

    /// @notice Mapping from user to their active offers
    mapping(address => bytes32[]) public userOffers;

    /// @notice Mapping from NFT contract + token ID to listing ID
    mapping(address => mapping(uint256 => bytes32)) public tokenListings;

    /// @notice Current listing fees
    ListingFees public listingFees;

    /// @notice Time constraints for listings
    TimeConstraints public timeConstraints;

    /// @notice Global statistics
    ListingStats public globalStats;

    /// @notice Mapping from user to their statistics
    mapping(address => SellerStats) public sellerStats;
    mapping(address => BuyerStats) public buyerStats;

    /// @notice Supported NFT contracts
    mapping(address => bool) public supportedContracts;

    /// @notice Maximum listings per user
    uint256 public maxListingsPerUser;

    /// @notice Maximum offers per user
    uint256 public maxOffersPerUser;

    /// @notice Listing ID counter
    uint256 private _listingIdCounter;

    /// @notice Offer ID counter
    uint256 private _offerIdCounter;

    /// @notice Bundle ID counter
    uint256 private _bundleIdCounter;

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures caller has required role
     */
    modifier onlyRole(bytes32 role) {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert AdvancedListing__MissingRole();
        }
        _;
    }

    /**
     * @notice Ensures listing exists and is valid
     */
    modifier validListing(bytes32 listingId) {
        if (listings[listingId].listingId == bytes32(0)) {
            revert AdvancedListing__ListingNotFound();
        }
        _;
    }

    /**
     * @notice Ensures listing is active
     */
    modifier activeListing(bytes32 listingId) {
        Listing storage listing = listings[listingId];
        if (listing.status != ListingStatus.ACTIVE) {
            revert AdvancedListing__ListingNotActive();
        }
        if (block.timestamp < listing.startTime) {
            revert AdvancedListing__ListingNotStarted();
        }
        if (block.timestamp > listing.endTime) {
            revert AdvancedListing__ListingExpired();
        }
        _;
    }

    /**
     * @notice Ensures caller is the seller
     */
    modifier onlySeller(bytes32 listingId) {
        if (listings[listingId].seller != msg.sender) {
            revert AdvancedListing__NotSeller();
        }
        _;
    }

    /**
     * @notice Ensures caller is not the seller
     */
    modifier notSeller(bytes32 listingId) {
        if (listings[listingId].seller == msg.sender) {
            revert AdvancedListing__CannotBuyOwnListing();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the AdvancedListingManager
     * @param _accessControl Address of the access control contract
     * @param _validator Address of the marketplace validator
     */
    constructor(address _accessControl, address _validator) Ownable(msg.sender) {
        if (_accessControl == address(0) || _validator == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        accessControl = MarketplaceAccessControl(_accessControl);
        validator = MarketplaceValidator(_validator);

        // Initialize default settings
        _initializeDefaults();
    }

    // ============================================================================
    // LISTING CREATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a fixed price listing
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param quantity Quantity to list (for ERC1155)
     * @param price Listing price
     * @param duration Listing duration in seconds
     * @param acceptOffers Whether to accept offers
     * @return listingId The created listing ID
     */
    function createFixedPriceListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        uint256 duration,
        bool acceptOffers
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        // Validate inputs
        _validateListingInputs(nftContract, tokenId, quantity, price, duration);

        // Check ownership and approval
        _validateOwnershipAndApproval(nftContract, tokenId, quantity, msg.sender);

        // Generate listing ID
        listingId = _generateListingId();

        // Create listing
        Listing storage listing = listings[listingId];
        listing.listingId = listingId;
        listing.listingType = ListingType.FIXED_PRICE;
        listing.status = ListingStatus.ACTIVE;
        listing.seller = msg.sender;
        listing.nftContract = nftContract;
        listing.tokenId = uint96(tokenId);
        listing.quantity = uint32(quantity);
        listing.price = uint96(price);
        listing.startTime = uint64(block.timestamp);
        listing.endTime = uint64(block.timestamp + duration);
        listing.acceptOffers = acceptOffers;

        // Update mappings
        _updateListingMappings(listingId, nftContract, tokenId);

        // Update statistics
        _updateListingStats(msg.sender, true);

        emit ListingCreated(
            listingId,
            ListingType.FIXED_PRICE,
            msg.sender,
            nftContract,
            tokenId,
            quantity,
            price,
            listing.startTime,
            listing.endTime
        );

        return listingId;
    }

    /**
     * @notice Creates an auction listing
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param quantity Quantity to list (for ERC1155)
     * @param params Auction parameters
     * @return listingId The created listing ID
     */
    function createAuctionListing(address nftContract, uint256 tokenId, uint256 quantity, AuctionParams calldata params)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 listingId)
    {
        // Validate inputs
        _validateAuctionParams(params);
        _validateListingInputs(nftContract, tokenId, quantity, params.startingPrice, params.duration);

        // Check ownership and approval
        _validateOwnershipAndApproval(nftContract, tokenId, quantity, msg.sender);

        // Generate listing ID
        listingId = _generateListingId();

        // Create listing
        Listing storage listing = listings[listingId];
        listing.listingId = listingId;
        listing.listingType = ListingType.AUCTION;
        listing.status = ListingStatus.ACTIVE;
        listing.seller = msg.sender;
        listing.nftContract = nftContract;
        listing.tokenId = uint96(tokenId);
        listing.quantity = uint32(quantity);
        listing.price = uint96(params.startingPrice);
        listing.startTime = uint64(block.timestamp);
        listing.endTime = uint64(block.timestamp + params.duration);
        listing.acceptOffers = false; // Auctions don't accept direct offers

        // Store auction parameters
        auctionParams[listingId] = params;

        // Update mappings
        _updateListingMappings(listingId, nftContract, tokenId);

        // Update statistics
        _updateListingStats(msg.sender, true);

        emit ListingCreated(
            listingId,
            ListingType.AUCTION,
            msg.sender,
            nftContract,
            tokenId,
            quantity,
            params.startingPrice,
            listing.startTime,
            listing.endTime
        );

        emit AuctionCreated(
            listingId,
            ListingType.AUCTION,
            msg.sender,
            params.startingPrice,
            params.reservePrice,
            params.duration,
            block.timestamp
        );

        return listingId;
    }

    /**
     * @notice Creates a Dutch auction listing
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param quantity Quantity to list (for ERC1155)
     * @param params Dutch auction parameters
     * @return listingId The created listing ID
     */
    function createDutchAuctionListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        DutchAuctionParams calldata params
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        // Validate inputs
        _validateDutchAuctionParams(params);
        _validateListingInputs(nftContract, tokenId, quantity, params.startingPrice, params.duration);

        // Check ownership and approval
        _validateOwnershipAndApproval(nftContract, tokenId, quantity, msg.sender);

        // Generate listing ID
        listingId = _generateListingId();

        // Create listing
        Listing storage listing = listings[listingId];
        listing.listingId = listingId;
        listing.listingType = ListingType.DUTCH_AUCTION;
        listing.status = ListingStatus.ACTIVE;
        listing.seller = msg.sender;
        listing.nftContract = nftContract;
        listing.tokenId = uint96(tokenId);
        listing.quantity = uint32(quantity);
        listing.price = uint96(params.startingPrice);
        listing.startTime = uint64(block.timestamp);
        listing.endTime = uint64(block.timestamp + params.duration);
        listing.acceptOffers = false;

        // Store Dutch auction parameters
        dutchAuctionParams[listingId] = params;

        // Update mappings
        _updateListingMappings(listingId, nftContract, tokenId);

        // Update statistics
        _updateListingStats(msg.sender, true);

        emit ListingCreated(
            listingId,
            ListingType.DUTCH_AUCTION,
            msg.sender,
            nftContract,
            tokenId,
            quantity,
            params.startingPrice,
            listing.startTime,
            listing.endTime
        );

        emit AuctionCreated(
            listingId,
            ListingType.DUTCH_AUCTION,
            msg.sender,
            params.startingPrice,
            params.endingPrice,
            params.duration,
            block.timestamp
        );

        return listingId;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Initializes default contract settings
     */
    function _initializeDefaults() internal {
        // Set default fees (2.5% marketplace fee)
        listingFees = ListingFees({
            baseFee: 0,
            percentageFee: 250, // 2.5%
            auctionFee: 50, // Additional 0.5% for auctions
            bundleFee: 100, // Additional 1% for bundles
            offerFee: 0.001 ether, // Fixed fee for offers
            feeRecipient: owner()
        });

        // Set default time constraints
        timeConstraints = TimeConstraints({
            minListingDuration: MIN_LISTING_DURATION,
            maxListingDuration: MAX_LISTING_DURATION,
            minAuctionDuration: MIN_AUCTION_DURATION,
            maxAuctionDuration: MAX_AUCTION_DURATION,
            offerValidityPeriod: DEFAULT_OFFER_VALIDITY,
            gracePeriod: GRACE_PERIOD
        });

        // Set default limits
        maxListingsPerUser = 100;
        maxOffersPerUser = 50;
    }

    /**
     * @notice Validates listing inputs
     */
    function _validateListingInputs(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        uint256 duration
    ) internal view {
        if (nftContract == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        if (!supportedContracts[nftContract]) {
            revert AdvancedListing__UnsupportedNFTContract();
        }

        if (price == 0) {
            revert AdvancedListing__InvalidPrice();
        }

        if (quantity == 0) {
            revert AdvancedListing__InsufficientQuantity();
        }

        if (duration < timeConstraints.minListingDuration || duration > timeConstraints.maxListingDuration) {
            revert AdvancedListing__InvalidDuration();
        }

        // Check if token is already listed
        if (tokenListings[nftContract][tokenId] != bytes32(0)) {
            revert AdvancedListing__TokenAlreadyListed();
        }

        // Check user listing limit
        if (userListings[msg.sender].length >= maxListingsPerUser) {
            revert AdvancedListing__MaxListingsExceeded();
        }
    }

    /**
     * @notice Validates ownership and approval
     */
    function _validateOwnershipAndApproval(address nftContract, uint256 tokenId, uint256 quantity, address owner)
        internal
        view
    {
        // Check if it's ERC721 or ERC1155
        try IERC165(nftContract).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
            if (isERC721) {
                // ERC721 validation
                if (IERC721(nftContract).ownerOf(tokenId) != owner) {
                    revert AdvancedListing__NotTokenOwner();
                }

                if (
                    !IERC721(nftContract).isApprovedForAll(owner, address(this))
                        && IERC721(nftContract).getApproved(tokenId) != address(this)
                ) {
                    revert AdvancedListing__NotApproved();
                }
            } else {
                // ERC1155 validation
                if (IERC1155(nftContract).balanceOf(owner, tokenId) < quantity) {
                    revert AdvancedListing__InsufficientQuantity();
                }

                if (!IERC1155(nftContract).isApprovedForAll(owner, address(this))) {
                    revert AdvancedListing__NotApproved();
                }
            }
        } catch {
            revert AdvancedListing__UnsupportedNFTContract();
        }
    }

    /**
     * @notice Validates auction parameters
     */
    function _validateAuctionParams(AuctionParams calldata params) internal view {
        if (params.startingPrice == 0) {
            revert AdvancedListing__InvalidPrice();
        }

        if (
            params.duration < timeConstraints.minAuctionDuration || params.duration > timeConstraints.maxAuctionDuration
        ) {
            revert AdvancedListing__InvalidDuration();
        }

        if (params.reservePrice > 0 && params.reservePrice < params.startingPrice) {
            revert AdvancedListing__InvalidAuctionParams();
        }

        if (params.buyNowPrice > 0 && params.buyNowPrice <= params.startingPrice) {
            revert AdvancedListing__InvalidAuctionParams();
        }

        if (params.bidIncrement < MIN_BID_INCREMENT || params.bidIncrement > MAX_BID_INCREMENT) {
            revert AdvancedListing__InvalidAuctionParams();
        }
    }

    /**
     * @notice Validates Dutch auction parameters
     */
    function _validateDutchAuctionParams(DutchAuctionParams calldata params) internal view {
        if (params.startingPrice == 0 || params.endingPrice == 0) {
            revert AdvancedListing__InvalidPrice();
        }

        if (params.startingPrice <= params.endingPrice) {
            revert AdvancedListing__InvalidDutchAuctionParams();
        }

        if (
            params.duration < timeConstraints.minAuctionDuration || params.duration > timeConstraints.maxAuctionDuration
        ) {
            revert AdvancedListing__InvalidDuration();
        }

        if (params.priceDropInterval == 0 || params.priceDropAmount == 0) {
            revert AdvancedListing__InvalidDutchAuctionParams();
        }
    }

    /**
     * @notice Updates listing mappings
     */
    function _updateListingMappings(bytes32 listingId, address nftContract, uint256 tokenId) internal {
        userListings[msg.sender].push(listingId);
        tokenListings[nftContract][tokenId] = listingId;
    }

    /**
     * @notice Updates listing statistics
     */
    function _updateListingStats(address seller, bool isNewListing) internal {
        if (isNewListing) {
            globalStats.totalListings++;
            globalStats.activeListings++;
            sellerStats[seller].totalListings++;
        }
    }

    /**
     * @notice Generates a unique listing ID
     */
    function _generateListingId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), msg.sender, block.timestamp, _listingIdCounter++));
    }

    // ============================================================================
    // PURCHASE FUNCTIONS
    // ============================================================================

    /**
     * @notice Purchases an NFT at fixed price
     * @param listingId The listing ID to purchase
     */
    function buyNow(bytes32 listingId)
        external
        payable
        nonReentrant
        whenNotPaused
        validListing(listingId)
        activeListing(listingId)
        notSeller(listingId)
    {
        Listing storage listing = listings[listingId];

        // Validate listing type supports buy now
        if (!supportsBuyNow(listing.listingType)) {
            revert AdvancedListing__UnsupportedListingType();
        }

        // Check payment
        if (msg.value != listing.price) {
            revert AdvancedListing__IncorrectPayment();
        }

        // Process purchase
        _processPurchase(listingId, msg.sender, listing.price);
    }

    /**
     * @notice Gets current price for Dutch auction
     * @param listingId The listing ID
     * @return currentPrice The current price
     */
    function getCurrentDutchAuctionPrice(bytes32 listingId)
        external
        view
        validListing(listingId)
        returns (uint256 currentPrice)
    {
        Listing storage listing = listings[listingId];

        if (listing.listingType != ListingType.DUTCH_AUCTION) {
            revert AdvancedListing__UnsupportedListingType();
        }

        DutchAuctionParams storage params = dutchAuctionParams[listingId];

        uint256 elapsed = block.timestamp - listing.startTime;
        uint256 intervals = elapsed / params.priceDropInterval;
        uint256 totalDrop = intervals * params.priceDropAmount;

        if (totalDrop >= (params.startingPrice - params.endingPrice)) {
            return params.endingPrice;
        }

        return params.startingPrice - totalDrop;
    }

    /**
     * @notice Purchases Dutch auction at current price
     * @param listingId The listing ID to purchase
     */
    function buyDutchAuction(bytes32 listingId)
        external
        payable
        nonReentrant
        whenNotPaused
        validListing(listingId)
        activeListing(listingId)
        notSeller(listingId)
    {
        Listing storage listing = listings[listingId];

        if (listing.listingType != ListingType.DUTCH_AUCTION) {
            revert AdvancedListing__UnsupportedListingType();
        }

        uint256 currentPrice = this.getCurrentDutchAuctionPrice(listingId);

        if (msg.value != currentPrice) {
            revert AdvancedListing__IncorrectPayment();
        }

        // Process purchase
        _processPurchase(listingId, msg.sender, currentPrice);
    }

    // ============================================================================
    // LISTING MANAGEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Updates listing price and/or end time
     * @param listingId The listing ID to update
     * @param newPrice New price (0 to keep current)
     * @param newEndTime New end time (0 to keep current)
     */
    function updateListing(bytes32 listingId, uint256 newPrice, uint256 newEndTime)
        external
        nonReentrant
        whenNotPaused
        validListing(listingId)
        onlySeller(listingId)
    {
        Listing storage listing = listings[listingId];

        if (listing.status != ListingStatus.ACTIVE) {
            revert AdvancedListing__ListingNotActive();
        }

        // Cannot update auction listings with bids
        if (isAuctionType(listing.listingType)) {
            revert AdvancedListing__UnsupportedListingType();
        }

        uint256 oldPrice = listing.price;
        uint256 oldEndTime = listing.endTime;

        if (newPrice > 0) {
            listing.price = uint96(newPrice);
        }

        if (newEndTime > 0) {
            if (newEndTime <= block.timestamp) {
                revert AdvancedListing__InvalidTimeParams();
            }
            listing.endTime = uint64(newEndTime);
        }

        emit ListingUpdated(
            listingId, msg.sender, oldPrice, listing.price, oldEndTime, listing.endTime, block.timestamp
        );
    }

    /**
     * @notice Cancels a listing
     * @param listingId The listing ID to cancel
     * @param reason Reason for cancellation
     */
    function cancelListing(bytes32 listingId, string calldata reason)
        external
        nonReentrant
        whenNotPaused
        validListing(listingId)
        onlySeller(listingId)
    {
        Listing storage listing = listings[listingId];

        if (listing.status != ListingStatus.ACTIVE) {
            revert AdvancedListing__ListingNotActive();
        }

        // Update status
        listing.status = ListingStatus.CANCELLED;

        // Remove from token mapping
        delete tokenListings[listing.nftContract][listing.tokenId];

        // Update statistics
        globalStats.activeListings--;
        sellerStats[listing.seller].cancelledListings++;

        emit ListingCancelled(listingId, msg.sender, reason, block.timestamp);
    }

    // ============================================================================
    // INTERNAL PURCHASE LOGIC
    // ============================================================================

    /**
     * @notice Processes a purchase transaction
     * @param listingId The listing ID
     * @param buyer The buyer address
     * @param price The purchase price
     * @dev Follows checks-effects-interactions pattern to prevent reentrancy
     * @dev All state changes occur before external calls
     */
    function _processPurchase(bytes32 listingId, address buyer, uint256 price) internal {
        Listing storage listing = listings[listingId];

        // Calculate fees and royalties
        uint256 totalFees = _calculateFees(price, listing.listingType);
        (address royaltyRecipient, uint256 royaltyAmount) =
            _calculateRoyalty(listing.nftContract, listing.tokenId, price);

        uint256 sellerAmount = price - totalFees - royaltyAmount;

        // ============================================================================
        // EFFECTS: Update all state BEFORE external calls (reentrancy protection)
        // ============================================================================

        // Cache seller address before state changes
        address seller = listing.seller;

        // Update listing status
        listing.status = ListingStatus.SOLD;

        // Remove from token mapping
        delete tokenListings[listing.nftContract][listing.tokenId];

        // Update statistics
        _updatePurchaseStats(seller, buyer, price);

        emit NFTPurchased(
            listingId,
            buyer,
            seller,
            listing.nftContract,
            listing.tokenId,
            listing.quantity,
            price,
            totalFees,
            block.timestamp
        );

        // ============================================================================
        // INTERACTIONS: Make external calls AFTER state changes
        // ============================================================================

        // Transfer NFT
        _transferNFT(listing, buyer);

        // Transfer payments
        _transferPayments(seller, sellerAmount, royaltyRecipient, royaltyAmount, totalFees);
    }

    /**
     * @notice Calculates royalty information
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param price Sale price
     * @return recipient Royalty recipient address
     * @return amount Royalty amount
     */
    function _calculateRoyalty(address nftContract, uint256 tokenId, uint256 price)
        internal
        view
        returns (address recipient, uint256 amount)
    {
        try IERC2981(nftContract).royaltyInfo(tokenId, price) returns (address _recipient, uint256 _amount) {
            return (_recipient, _amount);
        } catch {
            return (address(0), 0);
        }
    }

    /**
     * @notice Transfers NFT to buyer using NFTTransferLib
     */
    function _transferNFT(Listing storage listing, address buyer) internal {
        // Create transfer parameters
        NFTTransferLib.TransferParams memory params = NFTTransferLib.createTransferParams(
            listing.nftContract, listing.tokenId, listing.quantity, listing.seller, buyer
        );

        // Execute transfer using library
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        if (!result.success) {
            revert AdvancedListing__TransferFailed();
        }
    }

    /**
     * @notice Transfers payments to respective parties using PaymentDistributionLib
     */
    function _transferPayments(
        address seller,
        uint256 sellerAmount,
        address royaltyRecipient,
        uint256 royaltyAmount,
        uint256 fees
    ) internal {
        // Calculate total amount for validation
        uint256 totalAmount = sellerAmount + royaltyAmount + fees;

        // Create payment data using library struct
        PaymentDistributionLib.PaymentData memory paymentData = PaymentDistributionLib.PaymentData({
            seller: seller,
            royaltyReceiver: royaltyRecipient,
            marketplaceWallet: listingFees.feeRecipient,
            totalAmount: totalAmount,
            sellerAmount: sellerAmount,
            marketplaceFee: fees,
            royaltyAmount: royaltyAmount
        });

        // Use library for distribution
        PaymentDistributionLib.distributePayment(paymentData);
    }

    /**
     * @notice Calculates total fees for a purchase
     */
    function _calculateFees(uint256 price, ListingType listingType) internal view returns (uint256) {
        uint256 percentageFee = calculatePercentageFee(price, listingFees.percentageFee);
        uint256 totalFees = listingFees.baseFee + percentageFee;

        if (isAuctionType(listingType)) {
            totalFees += listingFees.auctionFee;
        }

        return totalFees;
    }

    /**
     * @notice Updates purchase statistics
     */
    function _updatePurchaseStats(address seller, address buyer, uint256 price) internal {
        // Update global stats
        globalStats.activeListings--;
        globalStats.soldListings++;
        globalStats.totalVolume += price;
        globalStats.averagePrice = globalStats.totalVolume / globalStats.soldListings;

        // Update seller stats
        sellerStats[seller].successfulSales++;
        sellerStats[seller].totalRevenue += price;

        // Update buyer stats
        buyerStats[buyer].totalPurchases++;
        buyerStats[buyer].totalSpent += price;
        buyerStats[buyer].averagePurchasePrice = buyerStats[buyer].totalSpent / buyerStats[buyer].totalPurchases;
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets listing information
     * @param listingId The listing ID
     * @return listing The listing data
     */
    function getListing(bytes32 listingId) external view returns (Listing memory listing) {
        return listings[listingId];
    }

    /**
     * @notice Gets auction parameters for a listing
     * @param listingId The listing ID
     * @return params The auction parameters
     */
    function getAuctionParams(bytes32 listingId) external view returns (AuctionParams memory params) {
        return auctionParams[listingId];
    }

    /**
     * @notice Gets Dutch auction parameters for a listing
     * @param listingId The listing ID
     * @return params The Dutch auction parameters
     */
    function getDutchAuctionParams(bytes32 listingId) external view returns (DutchAuctionParams memory params) {
        return dutchAuctionParams[listingId];
    }

    /**
     * @notice Gets user's active listings
     * @param user The user address
     * @return listingIds Array of listing IDs
     */
    function getUserListings(address user) external view returns (bytes32[] memory listingIds) {
        return userListings[user];
    }

    /**
     * @notice Gets user's active offers
     * @param user The user address
     * @return offerIds Array of offer IDs
     */
    function getUserOffers(address user) external view returns (bytes32[] memory offerIds) {
        return userOffers[user];
    }

    /**
     * @notice Gets global marketplace statistics
     * @return stats The global statistics
     */
    function getGlobalStats() external view returns (ListingStats memory stats) {
        return globalStats;
    }

    /**
     * @notice Gets seller statistics
     * @param seller The seller address
     * @return stats The seller statistics
     */
    function getSellerStats(address seller) external view returns (SellerStats memory stats) {
        return sellerStats[seller];
    }

    /**
     * @notice Gets buyer statistics
     * @param buyer The buyer address
     * @return stats The buyer statistics
     */
    function getBuyerStats(address buyer) external view returns (BuyerStats memory stats) {
        return buyerStats[buyer];
    }

    /**
     * @notice Gets current listing fees
     * @return fees The current fee structure
     */
    function getListingFees() external view returns (ListingFees memory fees) {
        return listingFees;
    }

    /**
     * @notice Gets time constraints
     * @return constraints The current time constraints
     */
    function getTimeConstraints() external view returns (TimeConstraints memory constraints) {
        return timeConstraints;
    }

    /**
     * @notice Checks if NFT contract is supported
     * @param nftContract The NFT contract address
     * @return isSupported Whether the contract is supported
     */
    function isContractSupported(address nftContract) external view returns (bool isSupported) {
        return supportedContracts[nftContract];
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Sets supported NFT contract
     * @param nftContract The NFT contract address
     * @param isSupported Whether to support the contract
     */
    function setSupportedContract(address nftContract, bool isSupported) external onlyRole(accessControl.ADMIN_ROLE()) {
        if (nftContract == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        supportedContracts[nftContract] = isSupported;
    }

    /**
     * @notice Updates listing fees
     * @param newFees The new fee structure
     */
    function updateListingFees(ListingFees calldata newFees) external onlyRole(accessControl.ADMIN_ROLE()) {
        if (newFees.feeRecipient == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        if (newFees.percentageFee > MAX_FEE_PERCENTAGE) {
            revert AdvancedListing__FeeTooHigh();
        }

        ListingFees memory oldFees = listingFees;
        listingFees = newFees;

        emit FeeUpdated("listing", oldFees.percentageFee, newFees.percentageFee, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates time constraints
     * @param newConstraints The new time constraints
     */
    function updateTimeConstraints(TimeConstraints calldata newConstraints)
        external
        onlyRole(accessControl.ADMIN_ROLE())
    {
        if (
            newConstraints.minListingDuration == 0 || newConstraints.maxListingDuration == 0
                || newConstraints.minListingDuration >= newConstraints.maxListingDuration
        ) {
            revert AdvancedListing__InvalidTimeParams();
        }

        timeConstraints = newConstraints;
    }

    /**
     * @notice Updates user limits
     * @param newMaxListings Maximum listings per user
     * @param newMaxOffers Maximum offers per user
     */
    function updateUserLimits(uint256 newMaxListings, uint256 newMaxOffers)
        external
        onlyRole(accessControl.ADMIN_ROLE())
    {
        if (newMaxListings == 0 || newMaxOffers == 0) {
            revert AdvancedListing__InvalidParameter();
        }

        maxListingsPerUser = newMaxListings;
        maxOffersPerUser = newMaxOffers;
    }

    /**
     * @notice Emergency pause contract
     * @param reason Reason for pausing
     */
    function emergencyPause(string calldata reason) external onlyRole(accessControl.EMERGENCY_ROLE()) {
        _pause();
        emit ContractPaused(msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(accessControl.ADMIN_ROLE()) {
        _unpause();
        emit ContractUnpaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Updates access control contract
     * @param newAccessControl New access control contract address
     */
    function updateAccessControl(address newAccessControl) external onlyOwner {
        if (newAccessControl == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        accessControl = MarketplaceAccessControl(newAccessControl);
    }

    /**
     * @notice Updates validator contract
     * @param newValidator New validator contract address
     */
    function updateValidator(address newValidator) external onlyOwner {
        if (newValidator == address(0)) {
            revert AdvancedListing__ZeroAddress();
        }

        validator = MarketplaceValidator(newValidator);
    }
}
