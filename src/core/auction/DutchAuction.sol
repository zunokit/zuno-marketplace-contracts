// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseAuction} from "./BaseAuction.sol";
import {AuctionCreationParams, AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import "src/events/AuctionEvents.sol";
import "src/errors/AuctionErrors.sol";

/**
 * @title DutchAuction
 * @notice Implementation of Dutch (descending price) auctions
 * @dev Extends BaseAuction with Dutch auction specific functionality
 * @author NFT Marketplace Team
 */
contract DutchAuction is BaseAuction {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Minimum price drop percentage (1% = 100 basis points)
    uint256 public constant MIN_PRICE_DROP = 100;

    /// @notice Maximum price drop percentage (50% = 5000 basis points)
    uint256 public constant MAX_PRICE_DROP = 5000;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Mapping from auction ID to price drop percentage per hour
    mapping(bytes32 => uint256) public priceDropPerHour;

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the Dutch auction contract
     * @param _marketplaceWallet Address to receive marketplace fees
     */
    constructor(address _marketplaceWallet) BaseAuction(_marketplaceWallet) {}

    // ============================================================================
    // AUCTION CREATION
    // ============================================================================

    /**
     * @notice Creates a new Dutch auction (IAuction interface implementation)
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price/ending price)
     * @param duration Auction duration in seconds
     * @param auctionType Type of auction (must be DUTCH)
     * @param seller Address of the seller (NFT owner)
     * @return auctionId Unique identifier for the created auction
     * @dev Uses a default price drop of 5% per hour (500 basis points)
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
    ) external override whenNotPaused nonReentrant returns (bytes32 auctionId) {
        // Validate auction type
        if (auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Use default price drop of 5% per hour
        uint256 defaultPriceDropPerHour = 500; // 5%

        // Create the auction using base functionality
        AuctionCreationParams memory params = AuctionCreationParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            auctionType: AuctionType.DUTCH,
            seller: seller,
            bidIncrement: 0,
            extendOnBid: false
        });

        auctionId = _createAuctionInternal(params);

        // Store Dutch auction specific parameters
        priceDropPerHour[auctionId] = defaultPriceDropPerHour;

        return auctionId;
    }

    /**
     * @notice Creates a new Dutch auction with price drop configuration
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @param _priceDropPerHour Price drop percentage per hour (in basis points)
     * @param seller Address of the seller (NFT owner)
     * @return auctionId Unique identifier for the created auction
     */
    function createDutchAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 _priceDropPerHour,
        address seller
    ) external whenNotPaused nonReentrant returns (bytes32 auctionId) {
        // Validate price drop percentage
        if (_priceDropPerHour < MIN_PRICE_DROP || _priceDropPerHour > MAX_PRICE_DROP) {
            revert Auction__InvalidAuctionParameters();
        }

        // Create the auction using base functionality
        AuctionCreationParams memory params = AuctionCreationParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            auctionType: AuctionType.DUTCH,
            seller: seller,
            bidIncrement: 0,
            extendOnBid: false
        });

        auctionId = _createAuctionInternal(params);

        // Store Dutch auction specific parameters
        priceDropPerHour[auctionId] = _priceDropPerHour;

        return auctionId;
    }

    // ============================================================================
    // PURCHASE FUNCTIONS
    // ============================================================================

    /**
     * @notice Not applicable for Dutch auctions
     * @dev This function reverts as Dutch auctions use direct purchase, not bidding
     */
    function placeBid(bytes32) external payable override {
        revert Auction__UnsupportedAuctionType();
    }

    /**
     * @notice Purchases NFT in a Dutch auction at current price
     * @param auctionId Unique identifier of the auction
     */
    function buyNow(bytes32 auctionId)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyActiveAuction(auctionId)
        notSeller(auctionId)
    {
        _buyNowInternal(auctionId, msg.sender, msg.value);
    }

    /**
     * @notice Not applicable for Dutch auctions
     * @dev Dutch auctions don't have bid refunds
     */
    function withdrawBid(bytes32) external override {
        revert Auction__UnsupportedAuctionType();
    }

    // ============================================================================
    // FACTORY FUNCTIONS
    // ============================================================================

    /**
     * @notice Purchases NFT in a Dutch auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param buyer Address of the actual buyer
     */
    function buyNowFor(bytes32 auctionId, address buyer)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyActiveAuction(auctionId)
        onlyFactory
    {
        // Ensure buyer is not the seller
        if (auctions[auctionId].seller == buyer) {
            revert Auction__SellerCannotBid();
        }

        _buyNowInternal(auctionId, buyer, msg.value);
    }

    // ============================================================================
    // SETTLEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Settles a completed Dutch auction (if unsold)
     * @param auctionId Unique identifier of the auction to settle
     */
    function settleAuction(bytes32 auctionId) external override nonReentrant whenNotPaused auctionExists(auctionId) {
        Auction storage auction = auctions[auctionId];

        // Validate auction can be settled
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Auction__AuctionNotActive();
        }

        if (block.timestamp < auction.endTime) {
            revert Auction__AuctionStillActive();
        }

        if (auction.auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Dutch auction ended without sale
        auction.status = AuctionStatus.ENDED;
        _removeFromActiveAuctions(auctionId);

        emit AuctionSettled(auctionId, address(0), 0, auction.seller);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets current price for a Dutch auction
     * @param auctionId Unique identifier of the auction
     * @return currentPrice Current price of the Dutch auction
     */
    function getCurrentPrice(bytes32 auctionId) external view override returns (uint256 currentPrice) {
        Auction memory auction = auctions[auctionId];

        if (auction.auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        // For settled auctions, return the final price (highest bid)
        if (auction.status == AuctionStatus.SETTLED) {
            return auction.highestBid;
        }

        // For ended auctions, return the price at end time
        if (auction.status == AuctionStatus.ENDED) {
            return _calculatePriceAtTime(auctionId, auction.endTime);
        }

        // For active auctions, return current calculated price
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Auction__AuctionNotActive();
        }

        return _calculateCurrentPrice(auctionId);
    }

    /**
     * @notice Gets the price at a specific timestamp
     * @param auctionId Unique identifier of the auction
     * @param timestamp Timestamp to calculate price for
     * @return price Price at the specified timestamp
     */
    function getPriceAtTime(bytes32 auctionId, uint256 timestamp) external view returns (uint256 price) {
        Auction memory auction = auctions[auctionId];

        if (auction.auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        if (timestamp < auction.startTime) {
            return auction.startPrice;
        }

        if (timestamp >= auction.endTime) {
            return _calculatePriceAtTime(auctionId, auction.endTime);
        }

        return _calculatePriceAtTime(auctionId, timestamp);
    }

    /**
     * @notice Gets price drop configuration for an auction
     * @param auctionId Unique identifier of the auction
     * @return dropPerHour Price drop percentage per hour (in basis points)
     */
    function getPriceDropPerHour(bytes32 auctionId) external view returns (uint256 dropPerHour) {
        return priceDropPerHour[auctionId];
    }

    /**
     * @notice Calculates time remaining until price reaches reserve
     * @param auctionId Unique identifier of the auction
     * @return timeToReserve Time in seconds until reserve price is reached
     */
    function getTimeToReservePrice(bytes32 auctionId) external view returns (uint256 timeToReserve) {
        Auction memory auction = auctions[auctionId];

        if (auction.reservePrice == 0 || auction.reservePrice >= auction.startPrice) {
            return 0;
        }

        uint256 totalDrop = auction.startPrice - auction.reservePrice;
        uint256 dropPerSecond = (auction.startPrice * priceDropPerHour[auctionId]) / (BPS_DENOMINATOR * 3600);

        if (dropPerSecond == 0) {
            return type(uint256).max;
        }

        return totalDrop / dropPerSecond;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Internal function to handle Dutch auction purchase
     * @param auctionId The auction ID
     * @param buyer The buyer address
     * @param paymentAmount The payment amount
     */
    function _buyNowInternal(bytes32 auctionId, address buyer, uint256 paymentAmount) internal {
        Auction storage auction = auctions[auctionId];

        // Ensure this is a Dutch auction
        if (auction.auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Calculate current price and validate payment
        uint256 currentPrice = this.getCurrentPrice(auctionId);
        if (paymentAmount < currentPrice) {
            revert Auction__InsufficientPayment();
        }

        // Execute the purchase
        _executeDutchAuctionPurchase(auctionId, auction, buyer, currentPrice);

        // Handle excess payment refund
        _handleExcessRefund(buyer, paymentAmount, currentPrice);

        // Emit events
        emit DutchAuctionPurchase(auctionId, buyer, currentPrice, currentPrice);
        emit AuctionSettled(auctionId, buyer, currentPrice, auction.seller);
    }

    /**
     * @notice Executes the Dutch auction purchase
     * @param auctionId The auction ID
     * @param auction The auction storage reference
     * @param buyer The buyer address
     * @param currentPrice The current price
     */
    function _executeDutchAuctionPurchase(
        bytes32 auctionId,
        Auction storage auction,
        address buyer,
        uint256 currentPrice
    ) internal {
        // Transfer NFT to buyer
        _transferNFT(auction, buyer);

        // Distribute fees and payment
        _distributeFees(auctionId, currentPrice);

        // Update auction status
        auction.status = AuctionStatus.SETTLED;
        auction.highestBidder = buyer;
        auction.highestBid = currentPrice;
        _removeFromActiveAuctions(auctionId);
    }

    /**
     * @notice Handles excess payment refund
     * @param buyer The buyer address
     * @param paymentAmount The payment amount
     * @param currentPrice The current price
     */
    function _handleExcessRefund(address buyer, uint256 paymentAmount, uint256 currentPrice) internal {
        uint256 excess = paymentAmount - currentPrice;
        if (excess > 0) {
            (bool success,) = buyer.call{value: excess}("");
            if (!success) revert Auction__RefundFailed();
        }
    }

    /**
     * @notice Calculates current price based on time elapsed
     * @param auctionId The auction ID
     * @return currentPrice Current calculated price
     */
    function _calculateCurrentPrice(bytes32 auctionId) internal view returns (uint256 currentPrice) {
        return _calculatePriceAtTime(auctionId, block.timestamp);
    }

    /**
     * @notice Calculates price at a specific timestamp
     * @param auctionId The auction ID
     * @param timestamp The timestamp to calculate price for
     * @return price Price at the specified timestamp
     */
    function _calculatePriceAtTime(bytes32 auctionId, uint256 timestamp) internal view returns (uint256 price) {
        Auction memory auction = auctions[auctionId];

        if (timestamp <= auction.startTime) {
            return auction.startPrice;
        }

        uint256 timeElapsed = timestamp - auction.startTime;
        uint256 hoursElapsed = timeElapsed / 3600; // Convert seconds to hours
        uint256 remainingSeconds = timeElapsed % 3600;

        // Calculate price drop for complete hours
        uint256 totalDrop = (auction.startPrice * priceDropPerHour[auctionId] * hoursElapsed) / BPS_DENOMINATOR;

        // Calculate partial hour drop
        if (remainingSeconds > 0) {
            uint256 partialDrop =
                (auction.startPrice * priceDropPerHour[auctionId] * remainingSeconds) / (BPS_DENOMINATOR * 3600);
            totalDrop += partialDrop;
        }

        // Ensure price doesn't go below reserve
        if (totalDrop >= auction.startPrice) {
            return auction.reservePrice;
        }

        uint256 calculatedPrice = auction.startPrice - totalDrop;

        // Ensure price doesn't go below reserve
        if (calculatedPrice < auction.reservePrice) {
            return auction.reservePrice;
        }

        return calculatedPrice;
    }

    // ============================================================================
    // FACTORY FUNCTIONS
    // ============================================================================

    /**
     * @notice Cancels an auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param seller Address of the seller
     */
    function cancelAuctionFor(bytes32 auctionId, address seller)
        external
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyFactory
    {
        Auction storage auction = auctions[auctionId];

        // Validate auction can be cancelled
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Auction__AuctionNotActive();
        }

        if (auction.seller != seller) {
            revert Auction__NotAuctionSeller();
        }

        if (auction.auctionType != AuctionType.DUTCH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Cancel the auction
        auction.status = AuctionStatus.CANCELLED;
        _removeFromActiveAuctions(auctionId);

        // Notify validator about auction cancellation
        _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);

        emit AuctionCancelled(auctionId, seller, "Cancelled by seller");
    }

    /**
     * @notice Gets pending refund amount for a bidder
     * @return refundAmount Amount available for refund (always 0 for Dutch auctions)
     */
    function getPendingRefund(bytes32, address) external view override returns (uint256) {
        // Dutch auctions don't have bidding, so no refunds
        return 0;
    }
}
