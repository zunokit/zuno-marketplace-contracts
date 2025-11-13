// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAuction} from "src/interfaces/IAuction.sol";
import {IMarketplaceValidator} from "src/interfaces/IMarketplaceValidator.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RoyaltyLib} from "src/libraries/RoyaltyLib.sol";
import {NFTTransferLib} from "src/libraries/NFTTransferLib.sol";
import {NFTValidationLib} from "src/libraries/NFTValidationLib.sol";
import {
    Auction,
    Bid,
    AuctionStatus,
    AuctionType,
    AuctionCreationParams,
    DEFAULT_MIN_BID_INCREMENT
} from "src/types/AuctionTypes.sol";
import "src/events/AuctionEvents.sol";
import "src/errors/AuctionErrors.sol";

/**
 * @title BaseAuction
 * @notice Abstract base contract for all auction implementations
 * @dev Provides common functionality for English and Dutch auctions
 * @author NFT Marketplace Team
 */
abstract contract BaseAuction is IAuction, ReentrancyGuard, Pausable, Ownable {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Basis points denominator (100% = 10000)
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Default minimum auction duration (1 hour)
    uint256 public constant DEFAULT_MIN_DURATION = 1 hours;

    /// @notice Default maximum auction duration (30 days)
    uint256 public constant DEFAULT_MAX_DURATION = 30 days;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Marketplace wallet for fee collection
    address public marketplaceWallet;

    /// @notice Factory contract address (if deployed by factory)
    address public factoryContract;

    /// @notice Marketplace validator contract for cross-validation
    IMarketplaceValidator public marketplaceValidator;

    /// @notice Marketplace fee in basis points (default 2% = 200)
    uint256 public marketplaceFee = 200;

    /// @notice Minimum bid increment in basis points
    uint256 public minBidIncrement = DEFAULT_MIN_BID_INCREMENT;

    /// @notice Minimum auction duration
    uint256 public minAuctionDuration = DEFAULT_MIN_DURATION;

    /// @notice Maximum auction duration
    uint256 public maxAuctionDuration = DEFAULT_MAX_DURATION;

    /// @notice Mapping from auction ID to auction details
    mapping(bytes32 => Auction) public auctions;

    /// @notice Mapping from auction ID to array of bids
    mapping(bytes32 => Bid[]) public auctionBids;

    /// @notice Mapping from auction ID to bidder to bid index
    mapping(bytes32 => mapping(address => uint256)) public bidderToIndex;

    /// @notice Mapping from seller to array of auction IDs
    mapping(address => bytes32[]) public sellerAuctions;

    /// @notice Mapping from NFT contract to array of auction IDs
    mapping(address => bytes32[]) public contractAuctions;

    /// @notice Array of all auction IDs
    bytes32[] public allAuctions;

    /// @notice Array of active auction IDs
    bytes32[] public activeAuctions;

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures auction exists
     * @param auctionId The auction ID to check
     */
    modifier auctionExists(bytes32 auctionId) {
        if (auctions[auctionId].seller == address(0)) {
            revert Auction__AuctionNotFound();
        }
        _;
    }

    /**
     * @notice Ensures auction is active
     * @param auctionId The auction ID to check
     */
    modifier onlyActiveAuction(bytes32 auctionId) {
        if (!isAuctionActive(auctionId)) {
            revert Auction__AuctionNotActive();
        }
        _;
    }

    /**
     * @notice Ensures caller is the auction seller
     * @param auctionId The auction ID to check
     */
    modifier onlySeller(bytes32 auctionId) {
        if (auctions[auctionId].seller != msg.sender) {
            revert Auction__NotAuctionSeller();
        }
        _;
    }

    /**
     * @notice Ensures caller is not the auction seller
     * @param auctionId The auction ID to check
     */
    modifier notSeller(bytes32 auctionId) {
        if (auctions[auctionId].seller == msg.sender) {
            revert Auction__SellerCannotBid();
        }
        _;
    }

    /**
     * @notice Ensures caller is the factory contract
     */
    modifier onlyFactory() {
        if (msg.sender != factoryContract) {
            revert Auction__NotAuthorized();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the base auction contract
     * @param _marketplaceWallet Address to receive marketplace fees
     */
    constructor(address _marketplaceWallet) Ownable(msg.sender) {
        if (_marketplaceWallet == address(0)) {
            revert Auction__ZeroAddress();
        }
        marketplaceWallet = _marketplaceWallet;

        // factoryContract remains address(0) for standalone deployments
        // Factory-deployed contracts set this explicitly via initialize()
    }

    // ============================================================================
    // AUCTION MANAGEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a new auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @param auctionType Type of auction (English or Dutch)
     * @param seller Address of the seller (NFT owner)
     * @return auctionId Unique identifier for the created auction
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        AuctionType auctionType,
        address seller
    ) external virtual override whenNotPaused nonReentrant returns (bytes32 auctionId) {
        AuctionCreationParams memory params = AuctionCreationParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            auctionType: auctionType,
            seller: seller,
            bidIncrement: DEFAULT_MIN_BID_INCREMENT,
            extendOnBid: false
        });

        return _createAuctionInternal(params);
    }

    // Using AuctionCreationParams from AuctionTypes.sol instead of local struct

    /**
     * @notice Internal function to create auction (for child contracts)
     * @param params Auction parameters struct
     * @return auctionId Unique identifier for the created auction
     */
    function _createAuctionInternal(AuctionCreationParams memory params) internal returns (bytes32 auctionId) {
        // Validate parameters and ownership
        _validateAuctionCreation(params);

        // Generate unique auction ID
        auctionId = _generateAuctionId(params.nftContract, params.tokenId, params.seller, block.timestamp);

        // Create and store auction
        _createAndStoreAuction(auctionId, params);

        // Notify validator about auction creation
        _notifyValidatorAuctionCreated(params.nftContract, params.tokenId, params.seller, auctionId);

        return auctionId;
    }

    /**
     * @notice Cancels an active auction
     * @param auctionId Unique identifier of the auction to cancel
     */
    function cancelAuction(bytes32 auctionId)
        external
        virtual
        override
        auctionExists(auctionId)
        onlySeller(auctionId)
        nonReentrant
    {
        Auction storage auction = auctions[auctionId];

        // Check if auction can be cancelled
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Auction__AuctionNotActive();
        }

        // For English auctions with bids, this will be handled by child contracts
        // Base implementation only allows cancellation without bids
        if (auction.auctionType == AuctionType.ENGLISH && auction.bidCount > 0) {
            revert Auction__CannotCancelWithBids();
        }

        // Update auction status
        auction.status = AuctionStatus.CANCELLED;

        // Remove from active auctions
        _removeFromActiveAuctions(auctionId);

        // Notify validator about auction cancellation
        _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);

        // Emit event
        emit AuctionCancelled(auctionId, msg.sender, "Cancelled by seller");
    }

    // ============================================================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates auction creation parameters and ownership
     */
    function _validateAuctionCreation(AuctionCreationParams memory params) internal {
        _validateAuctionParameters(params);
        _validateNFTOwnership(params.nftContract, params.tokenId, params.amount, params.seller);
        _validateNFTAvailability(params.nftContract, params.tokenId, params.seller);
    }

    /**
     * @notice Validates auction creation parameters
     */
    function _validateAuctionParameters(AuctionCreationParams memory params) internal view {
        if (params.nftContract == address(0)) revert Auction__ZeroAddress();
        if (params.startPrice == 0) revert Auction__InvalidStartPrice();
        if (params.amount == 0) revert Auction__InvalidAuctionParameters();
        if (params.duration < minAuctionDuration || params.duration > maxAuctionDuration) {
            revert Auction__InvalidAuctionDuration();
        }
        // Reserve price can be higher than start price in English auctions
        // but should be reasonable (not more than 10x start price)
        if (params.reservePrice > params.startPrice * 10) {
            revert Auction__InvalidReservePrice();
        }
    }

    /**
     * @notice Validates NFT ownership and approval
     */
    function _validateNFTOwnership(address nftContract, uint256 tokenId, uint256 amount, address seller) internal view {
        // Check if it's ERC721 or ERC1155
        try IERC721(nftContract).supportsInterface(0x80ac58cd) returns (bool isERC721) {
            if (isERC721) {
                // ERC721 validation
                if (IERC721(nftContract).ownerOf(tokenId) != seller) {
                    revert Auction__NotNFTOwner();
                }
                // For factory-deployed auctions, defer approval enforcement to transfer time
                if (factoryContract == address(0)) {
                    // Standalone deployments must have approval for this contract
                    address approvedContract = address(this);
                    if (
                        !IERC721(nftContract).isApprovedForAll(seller, approvedContract)
                            && IERC721(nftContract).getApproved(tokenId) != approvedContract
                    ) {
                        revert Auction__NFTNotApproved();
                    }
                }
            } else {
                // ERC1155 validation
                if (IERC1155(nftContract).balanceOf(seller, tokenId) < amount) {
                    revert Auction__NotNFTOwner();
                }
                // For factory-deployed auctions, defer approval enforcement to transfer time
                if (factoryContract == address(0)) {
                    // Standalone deployments must have approval for this contract
                    address approvedContract = address(this);
                    if (!IERC1155(nftContract).isApprovedForAll(seller, approvedContract)) {
                        revert Auction__NFTNotApproved();
                    }
                }
            }
        } catch {
            revert Auction__UnsupportedAuctionType();
        }
    }

    /**
     * @notice Validates NFT availability for auction (not already listed)
     */
    function _validateNFTAvailability(address nftContract, uint256 tokenId, address seller) internal {
        // Skip validation if validator is not set
        if (address(marketplaceValidator) == address(0)) {
            return;
        }

        // Check if NFT is available for auction
        (bool isAvailable, IMarketplaceValidator.NFTStatus status) =
            marketplaceValidator.isNFTAvailable(nftContract, tokenId, seller);

        // Emit detailed debug info for troubleshooting
        emit DebugNFTValidation(nftContract, tokenId, seller, isAvailable, uint8(status), block.timestamp);

        if (!isAvailable) {
            if (status == IMarketplaceValidator.NFTStatus.LISTED) {
                revert Auction__NFTAlreadyListed();
            } else if (status == IMarketplaceValidator.NFTStatus.IN_AUCTION) {
                revert Auction__NFTAlreadyInAuction();
            } else {
                revert Auction__NFTNotAvailable();
            }
        }
    }

    /**
     * @notice Creates and stores auction with all mappings
     */
    function _createAndStoreAuction(bytes32 auctionId, AuctionCreationParams memory params) internal {
        // Create auction struct
        Auction memory newAuction = Auction({
            auctionId: auctionId,
            nftContract: params.nftContract,
            tokenId: params.tokenId,
            amount: params.amount,
            seller: params.seller,
            startPrice: params.startPrice,
            reservePrice: params.reservePrice,
            startTime: block.timestamp,
            endTime: block.timestamp + params.duration,
            status: AuctionStatus.ACTIVE,
            auctionType: params.auctionType,
            highestBidder: address(0),
            highestBid: 0,
            bidCount: 0
        });

        // Store auction and update mappings
        _storeAuctionAndUpdateMappings(newAuction, params.seller, params.nftContract);

        // Emit event
        _emitAuctionCreatedEvent(newAuction);
    }

    /**
     * @notice Generates unique auction ID
     */
    function _generateAuctionId(address nftContract, uint256 tokenId, address seller, uint256 timestamp)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(nftContract, tokenId, seller, timestamp));
    }

    /**
     * @notice Stores auction and updates all mappings
     */
    function _storeAuctionAndUpdateMappings(Auction memory newAuction, address seller, address nftContract) internal {
        bytes32 auctionId = newAuction.auctionId;

        // Store auction
        auctions[auctionId] = newAuction;

        // Update mappings
        sellerAuctions[seller].push(auctionId);
        contractAuctions[nftContract].push(auctionId);
        allAuctions.push(auctionId);
        activeAuctions.push(auctionId);
    }

    /**
     * @notice Emits auction created event
     */
    function _emitAuctionCreatedEvent(Auction memory auction) internal {
        emit AuctionCreated(
            auction.auctionId,
            auction.nftContract,
            auction.tokenId,
            auction.seller,
            auction.startPrice,
            auction.reservePrice,
            auction.startTime,
            auction.endTime,
            uint8(auction.auctionType)
        );
    }

    /**
     * @notice Removes auction from active auctions array
     */
    function _removeFromActiveAuctions(bytes32 auctionId) internal {
        for (uint256 i = 0; i < activeAuctions.length; i++) {
            if (activeAuctions[i] == auctionId) {
                activeAuctions[i] = activeAuctions[activeAuctions.length - 1];
                activeAuctions.pop();
                break;
            }
        }
    }

    /**
     * @notice Notifies validator about auction creation
     */
    function _notifyValidatorAuctionCreated(address nftContract, uint256 tokenId, address seller, bytes32 auctionId)
        internal
    {
        if (address(marketplaceValidator) != address(0)) {
            try marketplaceValidator.setNFTInAuction(nftContract, tokenId, seller, auctionId) {}
                catch {
                // Silently fail if validator call fails
                // This prevents auction creation from failing due to validator issues
            }
        }
    }

    /**
     * @notice Notifies validator about auction cancellation
     */
    function _notifyValidatorAuctionCancelled(address nftContract, uint256 tokenId, address seller) internal {
        if (address(marketplaceValidator) != address(0)) {
            try marketplaceValidator.setNFTAvailable(nftContract, tokenId, seller) {}
                catch {
                // Silently fail if validator call fails
            }
        }
    }

    /**
     * @notice Notifies validator about auction settlement (NFT sold)
     */
    function _notifyValidatorAuctionSettled(address nftContract, uint256 tokenId, address oldOwner, address newOwner)
        internal
    {
        if (address(marketplaceValidator) != address(0)) {
            try marketplaceValidator.setNFTSold(nftContract, tokenId, oldOwner, newOwner) {}
                catch {
                // Silently fail if validator call fails
            }
        }
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets auction details
     * @param auctionId Unique identifier of the auction
     * @return auction Auction struct with all details
     */
    function getAuction(bytes32 auctionId) external view override returns (Auction memory auction) {
        return auctions[auctionId];
    }

    /**
     * @notice Checks if an auction is active
     * @param auctionId Unique identifier of the auction
     * @return isActive Whether the auction is currently active
     */
    function isAuctionActive(bytes32 auctionId) public view override returns (bool isActive) {
        Auction memory auction = auctions[auctionId];
        return auction.status == AuctionStatus.ACTIVE && block.timestamp >= auction.startTime
            && block.timestamp <= auction.endTime;
    }

    // ============================================================================
    // VIEW FUNCTIONS CONTINUED
    // ============================================================================

    /**
     * @notice Gets bid details for a specific bidder
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the bidder
     * @return bid Bid struct with details
     */
    function getBid(bytes32 auctionId, address bidder) external view override returns (Bid memory bid) {
        uint256 index = bidderToIndex[auctionId][bidder];
        if (index == 0 && auctionBids[auctionId].length == 0) {
            return Bid(address(0), 0, 0, false);
        }
        return auctionBids[auctionId][index];
    }

    /**
     * @notice Gets all bids for an auction
     * @param auctionId Unique identifier of the auction
     * @return bids Array of all bids
     */
    function getAllBids(bytes32 auctionId) external view override returns (Bid[] memory bids) {
        return auctionBids[auctionId];
    }

    /**
     * @notice Gets auctions by seller
     * @param seller Address of the seller
     * @return auctionIds Array of auction IDs
     */
    function getAuctionsBySeller(address seller) external view override returns (bytes32[] memory auctionIds) {
        return sellerAuctions[seller];
    }

    /**
     * @notice Gets auctions by NFT contract
     * @param nftContract Address of the NFT contract
     * @return auctionIds Array of auction IDs
     */
    function getAuctionsByContract(address nftContract) external view override returns (bytes32[] memory auctionIds) {
        return contractAuctions[nftContract];
    }

    /**
     * @notice Gets active auctions
     * @return auctionIds Array of active auction IDs
     */
    function getActiveAuctions() external view override returns (bytes32[] memory auctionIds) {
        return activeAuctions;
    }

    /**
     * @notice Gets pending refund amount for a bidder
     * @return refundAmount Amount available for refund
     */
    function getPendingRefund(bytes32, address) external view virtual override returns (uint256 refundAmount) {
        // This will be implemented by child contracts
        return 0;
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Pauses/unpauses the auction contract
     * @param paused Whether to pause or unpause
     */
    function setPaused(bool paused) external override onlyOwner {
        if (paused) {
            if (this.paused()) {
                revert EnforcedPause();
            }
            _pause();
        } else {
            if (!this.paused()) {
                revert ExpectedPause();
            }
            _unpause();
        }
        emit AuctionFactoryPaused(paused, msg.sender);
    }

    /**
     * @notice Updates minimum auction duration
     * @param newMinDuration New minimum duration in seconds
     */
    function setMinAuctionDuration(uint256 newMinDuration) external override onlyOwner {
        if (newMinDuration == 0 || newMinDuration >= maxAuctionDuration) {
            revert Auction__InvalidAuctionDuration();
        }
        uint256 oldDuration = minAuctionDuration;
        minAuctionDuration = newMinDuration;
        emit AuctionParameterUpdated(bytes32(0), "minAuctionDuration", oldDuration, newMinDuration);
    }

    /**
     * @notice Updates maximum auction duration
     * @param newMaxDuration New maximum duration in seconds
     */
    function setMaxAuctionDuration(uint256 newMaxDuration) external override onlyOwner {
        if (newMaxDuration <= minAuctionDuration) {
            revert Auction__InvalidAuctionDuration();
        }
        uint256 oldDuration = maxAuctionDuration;
        maxAuctionDuration = newMaxDuration;
        emit AuctionParameterUpdated(bytes32(0), "maxAuctionDuration", oldDuration, newMaxDuration);
    }

    /**
     * @notice Updates minimum bid increment percentage
     * @param newIncrement New increment percentage (in basis points)
     */
    function setMinBidIncrement(uint256 newIncrement) external override onlyOwner {
        if (newIncrement == 0 || newIncrement > BPS_DENOMINATOR) {
            revert Auction__InvalidAuctionParameters();
        }
        uint256 oldIncrement = minBidIncrement;
        minBidIncrement = newIncrement;
        emit AuctionParameterUpdated(bytes32(0), "minBidIncrement", oldIncrement, newIncrement);
    }

    /**
     * @notice Updates marketplace fee
     * @param newFee New marketplace fee in basis points
     */
    function setMarketplaceFee(uint256 newFee) external onlyOwner {
        if (newFee > BPS_DENOMINATOR) {
            revert Auction__InvalidAuctionParameters();
        }
        uint256 oldFee = marketplaceFee;
        marketplaceFee = newFee;
        emit AuctionParameterUpdated(bytes32(0), "marketplaceFee", oldFee, newFee);
    }

    /**
     * @notice Updates marketplace wallet
     * @param newWallet New marketplace wallet address
     */
    function setMarketplaceWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) {
            revert Auction__ZeroAddress();
        }
        address oldWallet = marketplaceWallet;
        marketplaceWallet = newWallet;
        emit AuctionParameterUpdated(
            bytes32(0), "marketplaceWallet", uint256(uint160(oldWallet)), uint256(uint160(newWallet))
        );
    }

    /**
     * @notice Sets the marketplace validator contract
     * @param newValidator Address of the marketplace validator contract
     */
    function setMarketplaceValidator(address newValidator) external onlyOwner {
        address oldValidator = address(marketplaceValidator);
        marketplaceValidator = IMarketplaceValidator(newValidator);
        emit AuctionParameterUpdated(
            bytes32(0), "marketplaceValidator", uint256(uint160(oldValidator)), uint256(uint160(newValidator))
        );
    }

    // ============================================================================
    // INTERNAL UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Calculates and distributes fees
     * @param auctionId The auction ID
     * @param totalAmount Total amount to distribute
     * @return sellerAmount Amount going to seller after fees
     */
    function _distributeFees(bytes32 auctionId, uint256 totalAmount) internal returns (uint256 sellerAmount) {
        Auction memory auction = auctions[auctionId];

        // Calculate all fees
        (uint256 marketplaceFeeAmount, uint256 royaltyAmount, address royaltyReceiver) =
            _calculateFees(auction, totalAmount);

        // Calculate seller amount
        sellerAmount = totalAmount - marketplaceFeeAmount - royaltyAmount;

        // Distribute payments
        PaymentDistributionData memory paymentData = PaymentDistributionData({
            seller: auction.seller,
            royaltyReceiver: royaltyReceiver,
            sellerAmount: sellerAmount,
            marketplaceFeeAmount: marketplaceFeeAmount,
            royaltyAmount: royaltyAmount
        });

        _executePaymentDistribution(paymentData);

        // Emit fee distribution event
        emit AuctionFeesDistributed(auctionId, sellerAmount, marketplaceFeeAmount, royaltyAmount, royaltyReceiver);

        return sellerAmount;
    }

    /**
     * @notice Calculates marketplace and royalty fees
     * @param auction The auction details
     * @param totalAmount Total amount to calculate fees from
     * @return marketplaceFeeAmount Marketplace fee amount
     * @return royaltyAmount Royalty fee amount
     * @return royaltyReceiver Address to receive royalty
     */
    function _calculateFees(Auction memory auction, uint256 totalAmount)
        internal
        view
        returns (uint256 marketplaceFeeAmount, uint256 royaltyAmount, address royaltyReceiver)
    {
        // Calculate marketplace fee
        marketplaceFeeAmount = (totalAmount * marketplaceFee) / BPS_DENOMINATOR;

        // Calculate royalty fee using RoyaltyLib for comprehensive royalty detection
        (royaltyReceiver, royaltyAmount) =
            RoyaltyLib.calculateRoyalty(auction.nftContract, auction.tokenId, totalAmount);
    }

    // Struct to reduce stack depth in payment distribution
    struct PaymentDistributionData {
        address seller;
        address royaltyReceiver;
        uint256 sellerAmount;
        uint256 marketplaceFeeAmount;
        uint256 royaltyAmount;
    }

    /**
     * @notice Executes payment distribution to all parties
     * @param data Payment distribution data
     */
    function _executePaymentDistribution(PaymentDistributionData memory data) internal {
        // Transfer marketplace fee
        if (data.marketplaceFeeAmount > 0) {
            (bool success,) = marketplaceWallet.call{value: data.marketplaceFeeAmount}("");
            if (!success) revert Auction__PaymentDistributionFailed();
        }

        // Transfer royalty
        if (data.royaltyAmount > 0 && data.royaltyReceiver != address(0)) {
            (bool success,) = data.royaltyReceiver.call{value: data.royaltyAmount}("");
            if (!success) revert Auction__PaymentDistributionFailed();
        }

        // Transfer to seller
        if (data.sellerAmount > 0) {
            (bool success,) = data.seller.call{value: data.sellerAmount}("");
            if (!success) revert Auction__PaymentDistributionFailed();
        }
    }

    /**
     * @notice Transfers NFT from seller to buyer using NFTTransferLib
     * @param auction The auction details
     * @param to Address to transfer NFT to
     */
    function _transferNFT(Auction memory auction, address to) internal {
        // If called by factory, have factory transfer the NFT
        if (factoryContract != address(0)) {
            // Call factory's transfer function
            (bool success,) = factoryContract.call(
                abi.encodeWithSignature(
                    "transferNFTFromSeller(address,uint256,uint256,address,address)",
                    auction.nftContract,
                    auction.tokenId,
                    auction.amount,
                    auction.seller,
                    to
                )
            );
            if (!success) {
                revert Auction__NFTTransferFailed();
            }
        } else {
            // Direct transfer for standalone auction contracts using NFTTransferLib
            NFTTransferLib.TransferParams memory params = NFTTransferLib.createTransferParams(
                auction.nftContract, auction.tokenId, auction.amount, auction.seller, to
            );

            NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);
            if (!result.success) {
                revert Auction__NFTTransferFailed();
            }
        }
    }

    // ============================================================================
    // FACTORY FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction (called by factory)
     */
    function placeBidFor(bytes32, address) external payable virtual override onlyFactory {
        // This will be implemented by child contracts
        revert Auction__UnsupportedAuctionType();
    }

    /**
     * @notice Purchases NFT in a Dutch auction (called by factory)
     */
    function buyNowFor(bytes32, address) external payable virtual override onlyFactory {
        // This will be implemented by child contracts
        revert Auction__UnsupportedAuctionType();
    }

    /**
     * @notice Withdraws a refunded bid (called by factory)
     */
    function withdrawBidFor(bytes32, address) external virtual override onlyFactory {
        // This will be implemented by child contracts
        revert Auction__UnsupportedAuctionType();
    }

    /**
     * @notice Cancels an auction (called by factory)
     */
    function cancelAuctionFor(bytes32, address) external virtual override onlyFactory {
        // This will be implemented by child contracts
        revert Auction__UnsupportedAuctionType();
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Emergency function to reset NFT status in validator (admin only)
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param owner Owner of the NFT
     */
    function emergencyResetNFTStatus(address nftContract, uint256 tokenId, address owner) external onlyOwner {
        if (address(marketplaceValidator) != address(0)) {
            try marketplaceValidator.emergencyResetNFTStatus(nftContract, tokenId, owner) {}
                catch {
                // Silently fail if validator call fails
            }
        }
    }

    // ============================================================================
    // ABSTRACT FUNCTIONS (TO BE IMPLEMENTED BY CHILD CONTRACTS)
    // ============================================================================

    function placeBid(bytes32 auctionId) external payable virtual override;
    function buyNow(bytes32 auctionId) external payable virtual override;
    function settleAuction(bytes32 auctionId) external virtual override;
    function withdrawBid(bytes32 auctionId) external virtual override;
    function getCurrentPrice(bytes32 auctionId) external view virtual override returns (uint256);
}
