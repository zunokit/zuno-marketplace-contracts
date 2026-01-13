// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseAuction} from "./BaseAuction.sol";
import {AuctionCreationParams, AuctionType, AuctionStatus} from "src/types/AuctionTypes.sol";
import "src/events/AuctionEvents.sol";
import "src/errors/AuctionErrors.sol";

/**
 * @title EnglishAuction
 * @notice Implementation of English (ascending price) auctions
 * @dev Extends BaseAuction with English auction specific functionality
 * @author NFT Marketplace Team
 */
contract EnglishAuction is BaseAuction {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Time extension when bid is placed near auction end (10 minutes)
    uint256 public constant BID_EXTENSION_TIME = 10 minutes;

    /// @notice Time threshold for extending auction (5 minutes before end)
    uint256 public constant EXTENSION_THRESHOLD = 5 minutes;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Mapping from auction ID to pending refunds for bidders
    mapping(bytes32 => mapping(address => uint256)) public pendingRefunds;

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the English auction contract
     * @param _marketplaceWallet Address to receive marketplace fees
     */
    constructor(address _marketplaceWallet) BaseAuction(_marketplaceWallet) {}

    // ============================================================================
    // AUCTION CREATION
    // ============================================================================

    /**
     * @notice Creates a new English auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @param auctionType Type of auction (must be ENGLISH)
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
    ) external override whenNotPaused nonReentrant returns (bytes32 auctionId) {
        // Validate auction type
        if (auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Create the auction using base functionality
        AuctionCreationParams memory params = AuctionCreationParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            auctionType: auctionType,
            seller: seller,
            bidIncrement: 0,
            extendOnBid: false
        });

        auctionId = _createAuctionInternal(params);

        return auctionId;
    }

    // ============================================================================
    // BIDDING FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction
     * @param auctionId Unique identifier of the auction
     */
    function placeBid(bytes32 auctionId)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyActiveAuction(auctionId)
        notSeller(auctionId)
    {
        _placeBidInternal(auctionId, msg.sender, msg.value);
    }

    /**
     * @notice Not applicable for English auctions
     * @dev This function reverts as English auctions use bidding, not direct purchase
     */
    function buyNow(bytes32) external payable override {
        revert Auction__UnsupportedAuctionType();
    }

    /**
     * @notice Withdraws a refunded bid
     * @param auctionId Unique identifier of the auction
     */
    function withdrawBid(bytes32 auctionId) external override nonReentrant auctionExists(auctionId) {
        uint256 refundAmount = pendingRefunds[auctionId][msg.sender];

        if (refundAmount == 0) {
            revert Auction__NoBidToRefund();
        }

        // Clear the refund before transfer to prevent reentrancy
        pendingRefunds[auctionId][msg.sender] = 0;

        // Transfer refund
        (bool success,) = msg.sender.call{value: refundAmount}("");
        if (!success) {
            // Restore the refund amount if transfer fails
            pendingRefunds[auctionId][msg.sender] = refundAmount;
            revert Auction__RefundFailed();
        }

        // Update bid as refunded
        uint256 bidIndex = bidderToIndex[auctionId][msg.sender];
        if (bidIndex < auctionBids[auctionId].length) {
            auctionBids[auctionId][bidIndex].refunded = true;
        }

        emit BidRefunded(auctionId, msg.sender, refundAmount);
    }

    // ============================================================================
    // SETTLEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Settles a completed English auction
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

        if (auction.auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Check if there's a winner
        if (auction.highestBidder == address(0)) {
            // No bids - mark as ended
            auction.status = AuctionStatus.ENDED;
            _removeFromActiveAuctions(auctionId);
            emit AuctionSettled(auctionId, address(0), 0, auction.seller);
            return;
        }

        // Check reserve price
        if (auction.reservePrice > 0 && auction.highestBid < auction.reservePrice) {
            // Reserve not met - refund highest bidder and end auction
            pendingRefunds[auctionId][auction.highestBidder] += auction.highestBid;
            auction.status = AuctionStatus.ENDED;
            _removeFromActiveAuctions(auctionId);
            emit AuctionSettled(auctionId, address(0), 0, auction.seller);
            return;
        }

        // Successful auction - transfer NFT and distribute payment
        address winner = auction.highestBidder;
        uint256 winningBid = auction.highestBid;

        // Transfer NFT to winner
        _transferNFT(auction, winner);

        // Distribute fees and payment
        _distributeFees(auctionId, winningBid);

        // Update auction status
        auction.status = AuctionStatus.SETTLED;
        _removeFromActiveAuctions(auctionId);

        emit AuctionSettled(auctionId, winner, winningBid, auction.seller);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets current price for an English auction (highest bid)
     * @param auctionId Unique identifier of the auction
     * @return currentPrice Current highest bid or starting price if no bids
     */
    function getCurrentPrice(bytes32 auctionId) external view override returns (uint256 currentPrice) {
        Auction memory auction = auctions[auctionId];

        if (auction.auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // For all auction states, return highest bid or start price
        // This allows viewing final price even after auction ends/settles
        return auction.highestBid > 0 ? auction.highestBid : auction.startPrice;
    }

    /**
     * @notice Gets the minimum next bid amount
     * @param auctionId Unique identifier of the auction
     * @return minBid Minimum amount for next bid
     */
    function getMinNextBid(bytes32 auctionId) external view returns (uint256 minBid) {
        Auction memory auction = auctions[auctionId];

        if (auction.highestBid == 0) {
            return auction.startPrice;
        }

        uint256 increment = (auction.highestBid * minBidIncrement) / BPS_DENOMINATOR;
        return auction.highestBid + increment;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Internal function to place a bid
     * @param auctionId The auction ID
     * @param bidder The bidder address
     * @param bidAmount The bid amount
     */
    function _placeBidInternal(bytes32 auctionId, address bidder, uint256 bidAmount) internal {
        Auction storage auction = auctions[auctionId];

        // Ensure this is an English auction
        if (auction.auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Validate bid amount
        _validateBid(auctionId, bidAmount);

        // Process the bid
        _processBid(auctionId, auction, bidder, bidAmount);

        // Extend auction if bid placed near end
        _handleAuctionExtension(auctionId);

        // Emit bid placed event
        emit BidPlaced(auctionId, bidder, bidAmount, block.timestamp, true);
    }

    /**
     * @notice Processes a bid by updating auction state and handling refunds
     * @param auctionId The auction ID
     * @param auction The auction storage reference
     * @param bidder The bidder address
     * @param bidAmount The bid amount
     */
    function _processBid(bytes32 auctionId, Auction storage auction, address bidder, uint256 bidAmount) internal {
        // Handle previous highest bidder refund
        if (auction.highestBidder != address(0)) {
            pendingRefunds[auctionId][auction.highestBidder] += auction.highestBid;
        }

        // Clear any existing pending refunds for the new highest bidder
        // This prevents the bug where a user can withdraw while being highest bidder
        if (pendingRefunds[auctionId][bidder] > 0) {
            pendingRefunds[auctionId][bidder] = 0;
        }

        // Update auction with new highest bid
        auction.highestBidder = bidder;
        auction.highestBid = bidAmount;
        auction.bidCount++;

        // Store bid details
        _storeBidDetails(auctionId, bidder, bidAmount);
    }

    /**
     * @notice Stores bid details in the auction bids array
     * @param auctionId The auction ID
     * @param bidder The bidder address
     * @param bidAmount The bid amount
     */
    function _storeBidDetails(bytes32 auctionId, address bidder, uint256 bidAmount) internal {
        Bid memory newBid = Bid({bidder: bidder, amount: bidAmount, timestamp: block.timestamp, refunded: false});

        auctionBids[auctionId].push(newBid);
        bidderToIndex[auctionId][bidder] = auctionBids[auctionId].length - 1;
    }

    /**
     * @notice Validates a bid amount
     * @param auctionId The auction ID
     * @param bidAmount The bid amount to validate
     */
    function _validateBid(bytes32 auctionId, uint256 bidAmount) internal view {
        Auction memory auction = auctions[auctionId];

        if (bidAmount == 0) {
            revert Auction__BidTooLow();
        }

        if (auction.highestBid == 0) {
            // First bid must meet starting price
            if (bidAmount < auction.startPrice) {
                revert Auction__BidTooLow();
            }
        } else {
            // Subsequent bids must meet minimum increment
            uint256 minBid = auction.highestBid + ((auction.highestBid * minBidIncrement) / BPS_DENOMINATOR);

            if (bidAmount < minBid) {
                revert Auction__InsufficientBidIncrement();
            }
        }
    }

    /**
     * @notice Handles auction extension for last-minute bids
     * @param auctionId The auction ID
     */
    function _handleAuctionExtension(bytes32 auctionId) internal {
        Auction storage auction = auctions[auctionId];

        // Check if bid was placed within extension threshold
        if (auction.endTime - block.timestamp <= EXTENSION_THRESHOLD) {
            uint256 oldEndTime = auction.endTime;
            auction.endTime = block.timestamp + BID_EXTENSION_TIME;

            emit AuctionExtended(auctionId, oldEndTime, auction.endTime, "Last minute bid extension");
        }
    }

    // ============================================================================
    // FACTORY FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the actual bidder
     */
    function placeBidFor(bytes32 auctionId, address bidder)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyActiveAuction(auctionId)
        onlyFactory
    {
        // Ensure bidder is not the seller
        if (auctions[auctionId].seller == bidder) {
            revert Auction__SellerCannotBid();
        }

        _placeBidInternal(auctionId, bidder, msg.value);
    }

    /**
     * @notice Withdraws a refunded bid (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the actual bidder
     */
    function withdrawBidFor(bytes32 auctionId, address bidder)
        external
        override
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        onlyFactory
    {
        uint256 refundAmount = pendingRefunds[auctionId][bidder];

        if (refundAmount == 0) {
            revert Auction__NoBidToRefund();
        }

        // Clear the refund before transfer to prevent reentrancy
        pendingRefunds[auctionId][bidder] = 0;

        // Transfer refund
        (bool success,) = bidder.call{value: refundAmount}("");
        if (!success) {
            // Restore the refund amount if transfer fails
            pendingRefunds[auctionId][bidder] = refundAmount;
            revert Auction__RefundFailed();
        }

        // Update bid as refunded
        uint256 bidIndex = bidderToIndex[auctionId][bidder];
        if (bidIndex < auctionBids[auctionId].length) {
            auctionBids[auctionId][bidIndex].refunded = true;
        }

        emit BidRefunded(auctionId, bidder, refundAmount);
    }

    /**
     * @notice Cancels an auction (direct call by seller)
     * @param auctionId Unique identifier of the auction
     * @dev Updated to allow cancellation with bids - highest bidder is refunded
     */
    function cancelAuction(bytes32 auctionId)
        external
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

        if (auction.auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Store highest bidder information for refund BEFORE marking as cancelled
        // This prevents reentrancy attacks
        address highestBidder = auction.highestBidder;
        uint256 highestBid = auction.highestBid;

        // Mark as cancelled BEFORE refunds to prevent reentrancy
        auction.status = AuctionStatus.CANCELLED;
        auction.endTime = 0;
        _removeFromActiveAuctions(auctionId);

        // Refund highest bidder if there are any bids
        if (highestBidder != address(0) && highestBid > 0) {
            pendingRefunds[auctionId][highestBidder] += highestBid;
            emit BidRefunded(auctionId, highestBidder, highestBid);
        }

        // Emit events for ALL other pending refunds (for UX consistency with cancelAuctionFor)
        Bid[] storage bids = auctionBids[auctionId];
        for (uint256 i = 0; i < bids.length; i++) {
            address bidder = bids[i].bidder;
            uint256 pending = pendingRefunds[auctionId][bidder];

            if (pending > 0 && bidder != highestBidder) {
                emit BidRefunded(auctionId, bidder, pending);
            }
        }

        // Return NFT to seller using existing transfer function
        _transferNFT(auction, msg.sender);

        // Notify validator about auction cancellation
        _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);

        emit AuctionCancelled(auctionId, msg.sender, "Cancelled with bids - highest bidder refunded");
    }

    /**
     * @notice Cancels an auction (called by factory)
     * @param auctionId Unique identifier of the auction
     * @param seller Address of the seller
     * @dev Updated to allow cancellation with bids - highest bidder is refunded
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

        if (auction.auctionType != AuctionType.ENGLISH) {
            revert Auction__UnsupportedAuctionType();
        }

        // Store highest bidder information for refund BEFORE marking as cancelled
        // This prevents reentrancy attacks
        address highestBidder = auction.highestBidder;
        uint256 highestBid = auction.highestBid;

        // Mark as cancelled BEFORE refunds to prevent reentrancy
        auction.status = AuctionStatus.CANCELLED;
        auction.endTime = 0;
        _removeFromActiveAuctions(auctionId);

        // Refund highest bidder if there are any bids
        if (highestBidder != address(0) && highestBid > 0) {
            pendingRefunds[auctionId][highestBidder] += highestBid;
            emit BidRefunded(auctionId, highestBidder, highestBid);
        }

        // Emit events for ALL other pending refunds
        Bid[] storage bids = auctionBids[auctionId];
        for (uint256 i = 0; i < bids.length; i++) {
            address bidder = bids[i].bidder;
            uint256 pending = pendingRefunds[auctionId][bidder];

            if (pending > 0 && bidder != highestBidder) {
                emit BidRefunded(auctionId, bidder, pending);
            }
        }

        // Return NFT to seller using existing transfer function
        _transferNFT(auction, seller);

        // Notify validator about auction cancellation
        _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);

        emit AuctionCancelled(auctionId, seller, "Cancelled with bids - highest bidder refunded");
    }

    /**
     * @notice Refunds all bidders when auction is cancelled
     * @param auctionId The auction ID
     */
    function _refundAllBidders(bytes32 auctionId) internal {
        Auction storage auction = auctions[auctionId];

        // Highest bidder is handled directly in cancelAuctionFor; ensure others are marked refunded

        // Mark all bids as refunded in the bids array
        Bid[] storage bids = auctionBids[auctionId];
        for (uint256 i = 0; i < bids.length; i++) {
            if (!bids[i].refunded) {
                bids[i].refunded = true;
            }
        }

        emit AuctionCancelledWithRefunds(auctionId, auction.bidCount);
    }

    /**
     * @notice Gets pending refund amount for a bidder
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the bidder
     * @return refundAmount Amount available for refund
     */
    function getPendingRefund(bytes32 auctionId, address bidder)
        external
        view
        override
        returns (uint256 refundAmount)
    {
        return pendingRefunds[auctionId][bidder];
    }
}
