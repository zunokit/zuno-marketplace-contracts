// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseNFTExchange} from "src/common/BaseNFTExchange.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "src/errors/NFTExchangeErrors.sol";
import "src/events/NFTExchangeEvents.sol";
import {NFTValidationLib} from "src/libraries/NFTValidationLib.sol";
import {BatchOperationsLib} from "src/libraries/BatchOperationsLib.sol";
import {NFTTransferLib} from "src/libraries/NFTTransferLib.sol";
import {PaymentDistributionLib} from "src/libraries/PaymentDistributionLib.sol";

// ERC-1155 NFT Exchange Contract
contract ERC1155NFTExchange is BaseNFTExchange {
    /**
     * @notice Constructor for ERC1155NFTExchange
     * @dev Calls the parent BaseNFTExchange constructor
     */
    constructor() {
        // Constructor calls parent constructor which calls Ownable(msg.sender)
    }

    /**
     * @notice Initializes the ERC1155NFTExchange contract
     * @param m_marketplaceWallet The marketplace wallet address
     * @param m_owner The owner of the contract
     */
    function initialize(address m_marketplaceWallet, address m_owner) external initializer {
        __BaseNFTExchange_init(m_marketplaceWallet, m_owner);
    }

    /**
     * @notice Returns the supported NFT standard
     * @return standard The NFT standard (ERC1155)
     */
    function supportedStandard() public pure override returns (string memory) {
        return "ERC1155";
    }

    // Function to list a single ERC-1155 NFT
    function listNFT(
        address m_contractAddress,
        uint256 m_tokenId,
        uint256 m_amount,
        uint256 m_price,
        uint256 m_listingDuration
    ) public {
        // Validate basic parameters
        if (m_amount == 0) revert NFTExchange__AmountMustBeGreaterThanZero();
        if (m_price == 0) revert NFTExchange__PriceMustBeGreaterThanZero();
        if (m_listingDuration == 0) {
            revert NFTExchange__DurationMustBeGreaterThanZero();
        }

        // Use NFTValidationLib for comprehensive validation
        NFTValidationLib.ValidationParams memory validationParams =
            NFTValidationLib.createValidationParams(m_contractAddress, m_tokenId, m_amount, msg.sender, address(this));

        NFTValidationLib.ValidationResult memory result = NFTValidationLib.validateERC1155(validationParams);
        if (!result.isValid) {
            if (keccak256(bytes(result.errorMessage)) == keccak256(bytes("Insufficient balance"))) {
                revert NFTExchange__InsufficientBalance();
            } else if (keccak256(bytes(result.errorMessage)) == keccak256(bytes("Not approved"))) {
                revert NFTExchange__MarketplaceNotApproved();
            } else {
                revert NFTExchange__InsufficientBalance(); // Default fallback
            }
        }

        bytes32 m_listingId = _generateListingId(m_contractAddress, m_tokenId, msg.sender);
        _createListing(m_contractAddress, m_tokenId, m_price, m_listingDuration, m_amount, m_listingId);
    }

    // Function to batch list ERC-1155 NFTs (same collection)
    function batchListNFT(
        address m_contractAddress,
        uint256[] memory m_tokenIds,
        uint256[] memory m_amounts,
        uint256[] memory m_prices,
        uint256 m_listingDuration
    ) public {
        BatchOperationsLib.BatchListingParams memory params =
            BatchOperationsLib.BatchListingParams({
                nftContract: m_contractAddress,
                tokenIds: m_tokenIds,
                amounts: m_amounts,
                prices: m_prices,
                listingDuration: m_listingDuration,
                seller: msg.sender,
                spender: address(this)
            });
        (bool isValid, string memory errorMessage) = BatchOperationsLib.validateBatchListing(params);
        if (!isValid) {
            if (keccak256(bytes(errorMessage)) == keccak256(bytes("Array length mismatch"))) {
                revert NFTExchange__ArrayLengthMismatch();
            } else if (keccak256(bytes(errorMessage)) == keccak256(bytes("Invalid listing duration"))) {
                revert NFTExchange__DurationMustBeGreaterThanZero();
            } else if (keccak256(bytes(errorMessage)) == keccak256(bytes("Zero price not allowed"))) {
                revert NFTExchange__PriceMustBeGreaterThanZero();
            } else if (keccak256(bytes(errorMessage)) == keccak256(bytes("Zero amount not allowed"))) {
                revert NFTExchange__AmountMustBeGreaterThanZero();
            } else {
                revert NFTExchange__InsufficientBalance();
            }
        }
        for (uint256 i = 0; i < m_tokenIds.length; i++) {
            bytes32 listingId = _generateListingId(m_contractAddress, m_tokenIds[i], msg.sender);
            _createListing(m_contractAddress, m_tokenIds[i], m_prices[i], m_listingDuration, m_amounts[i], listingId);
            emit NFTListed(listingId, m_contractAddress, m_tokenIds[i], msg.sender, m_prices[i]);
        }
    }

    // Function to buy an ERC-1155 NFT (entire listing)
    function buyNFT(bytes32 m_listingId) public payable onlyActiveListing(m_listingId) nonReentrant {
        Listing storage s_listing = s_listings[m_listingId];
        _executePurchase(m_listingId, s_listing.amount);
    }

    // Function to buy a partial amount of ERC-1155 NFT
    function buyNFT(bytes32 m_listingId, uint256 m_amount) public payable onlyActiveListing(m_listingId) nonReentrant {
        if (m_amount == 0) {
            revert NFTExchange__AmountMustBeGreaterThanZero();
        }

        Listing storage s_listing = s_listings[m_listingId];
        if (m_amount > s_listing.amount) {
            revert NFTExchange__InsufficientBalance();
        }

        _executePurchase(m_listingId, m_amount);
    }

    // Internal function to execute purchase logic
    function _executePurchase(bytes32 m_listingId, uint256 m_purchaseAmount) internal {
        Listing storage s_listing = s_listings[m_listingId];

        // Calculate proportional price
        uint256 m_proportionalPrice = (s_listing.price * m_purchaseAmount) / s_listing.amount;

        (address m_royaltyReceiver, uint256 m_royalty) =
            getRoyaltyInfo(s_listing.contractAddress, s_listing.tokenId, m_proportionalPrice);

        uint256 m_takerFee;
        uint256 m_realityPrice;

        unchecked {
            // Safe: takerFee is always <= 10000 (basis points)
            m_takerFee = (m_proportionalPrice * s_takerFee) / BPS_DENOMINATOR;
            // Safe: addition of valid amounts
            m_realityPrice = m_proportionalPrice + m_royalty + m_takerFee;
        }

        if (msg.value < m_realityPrice) {
            revert NFTExchange__InsufficientPayment();
        }

        // Transfer NFT using NFTTransferLib
        NFTTransferLib.TransferParams memory transferParams = NFTTransferLib.createTransferParams(
            s_listing.contractAddress, s_listing.tokenId, m_purchaseAmount, s_listing.seller, msg.sender
        );

        NFTTransferLib.TransferResult memory transferResult = NFTTransferLib.transferERC1155(transferParams);
        if (!transferResult.success) {
            revert NFTExchange__TransferToSellerFailed();
        }

        PaymentDistribution memory payment = PaymentDistribution({
            seller: s_listing.seller,
            royaltyReceiver: m_royaltyReceiver,
            price: m_proportionalPrice,
            royalty: m_royalty,
            takerFee: m_takerFee,
            realityPrice: m_realityPrice
        });

        _distributePayments(payment);

        // Update listing amount
        s_listing.amount -= m_purchaseAmount;

        // If all tokens are sold, finalize the listing
        if (s_listing.amount == 0) {
            _finalizeListing(m_listingId, s_listing.contractAddress, s_listing.seller);
        } else {
            // Emit event for partial sale
            emit NFTSold(
                m_listingId,
                s_listing.contractAddress,
                s_listing.tokenId,
                s_listing.seller,
                msg.sender,
                m_proportionalPrice
            );
        }
    }

    // Struct to store batch purchase data to avoid stack too deep
    struct BatchPurchaseData {
        address royaltyReceiver;
        uint256 royalty;
        uint256 takerFee;
        uint256 realityPrice;
    }

    // Function to batch buy ERC-1155 NFTs (same collection)
    function batchBuyNFT(bytes32[] memory m_listingIds) public payable {
        if (m_listingIds.length == 0) revert NFTExchange__ArrayLengthMismatch();

        address contractAddress = s_listings[m_listingIds[0]].contractAddress;
        uint256 totalPrice = _validateAndCalculateBatchPrice(m_listingIds, contractAddress);

        if (msg.value < totalPrice) revert NFTExchange__InsufficientPayment();

        _executeBatchPurchase(m_listingIds, contractAddress);
    }

    // Internal function to validate listings and calculate total price
    function _validateAndCalculateBatchPrice(bytes32[] memory listingIds, address contractAddress)
        internal
        view
        returns (uint256 totalPrice)
    {
        for (uint256 i = 0; i < listingIds.length; i++) {
            Listing storage listing = s_listings[listingIds[i]];

            if (listing.status != ListingStatus.Active) {
                revert NFTExchange__NFTNotActive();
            }
            if (block.timestamp >= listing.listingStart + listing.listingDuration) {
                revert NFTExchange__ListingExpired();
            }
            if (listing.contractAddress != contractAddress) {
                revert NFTExchange__ArrayLengthMismatch();
            }

            BatchPurchaseData memory data = _calculatePurchaseData(listing);
            totalPrice += data.realityPrice;
        }
    }

    // Internal function to calculate purchase data for a listing
    function _calculatePurchaseData(Listing storage listing) internal view returns (BatchPurchaseData memory data) {
        (data.royaltyReceiver, data.royalty) = getRoyaltyInfo(listing.contractAddress, listing.tokenId, listing.price);
        data.takerFee = (listing.price * s_takerFee) / BPS_DENOMINATOR;
        data.realityPrice = listing.price + data.royalty + data.takerFee;
    }

    // Internal function to execute batch purchase
    function _executeBatchPurchase(bytes32[] memory listingIds, address contractAddress) internal {
        for (uint256 i = 0; i < listingIds.length; i++) {
            _executeSinglePurchase(listingIds[i], contractAddress);
        }
    }

    // Internal function to execute a single purchase within batch
    function _executeSinglePurchase(bytes32 listingId, address contractAddress) internal {
        Listing storage listing = s_listings[listingId];
        BatchPurchaseData memory data = _calculatePurchaseData(listing);

        // Transfer NFT using NFTTransferLib
        NFTTransferLib.TransferParams memory transferParams = NFTTransferLib.createTransferParams(
            contractAddress, listing.tokenId, listing.amount, listing.seller, msg.sender
        );

        NFTTransferLib.TransferResult memory transferResult = NFTTransferLib.transferERC1155(transferParams);
        if (!transferResult.success) {
            revert NFTExchange__TransferToSellerFailed();
        }

        // Distribute payments
        PaymentDistribution memory payment = PaymentDistribution({
            seller: listing.seller,
            royaltyReceiver: data.royaltyReceiver,
            price: listing.price,
            royalty: data.royalty,
            takerFee: data.takerFee,
            realityPrice: data.realityPrice
        });

        _distributePayments(payment);

        // Finalize listing
        _finalizeListing(listingId, listing.contractAddress, listing.seller);
    }

    // Function to cancel listing
    function cancelListing(bytes32 m_listingId) public onlyActiveListing(m_listingId) {
        Listing storage s_listing = s_listings[m_listingId];
        if (s_listing.seller != msg.sender) revert NFTExchange__NotTheOwner();
        s_listings[m_listingId].status = ListingStatus.Cancelled;
        _removeListingFromArray(s_listingsByCollection[s_listing.contractAddress], m_listingId);
        _removeListingFromArray(s_listingsBySeller[s_listing.seller], m_listingId);

        // Remove from active listings
        s_activeListings[s_listing.contractAddress][s_listing.tokenId][s_listing.seller] = bytes32(0);

        emit ListingCancelled(m_listingId, s_listing.contractAddress, s_listing.tokenId, s_listing.seller);
    }

    // Function to batch cancel listings
    function batchCancelListing(bytes32[] memory m_listingIds) public {
        uint256 length = m_listingIds.length;
        for (uint256 i = 0; i < length; i++) {
            _cancelSingleListing(m_listingIds[i]);
        }
    }

    // Internal function to cancel a single listing
    function _cancelSingleListing(bytes32 listingId) internal {
        Listing storage listing = s_listings[listingId];

        // Validate listing can be cancelled
        _validateListingCancellation(listing);

        // Update listing status
        listing.status = ListingStatus.Cancelled;

        // Remove from arrays and mappings
        _removeCancelledListing(listingId, listing);

        // Emit cancellation event
        emit ListingCancelled(listingId, listing.contractAddress, listing.tokenId, listing.seller);
    }

    // Internal function to validate listing cancellation
    function _validateListingCancellation(Listing storage listing) internal view {
        if (listing.status != ListingStatus.Active) {
            revert NFTExchange__NFTNotActive();
        }
        if (block.timestamp >= listing.listingStart + listing.listingDuration) {
            revert NFTExchange__ListingExpired();
        }
        if (listing.seller != msg.sender) {
            revert NFTExchange__NotTheOwner();
        }
    }

    // Internal function to remove cancelled listing from arrays
    function _removeCancelledListing(bytes32 listingId, Listing storage listing) internal {
        _removeListingFromArray(s_listingsByCollection[listing.contractAddress], listingId);
        _removeListingFromArray(s_listingsBySeller[listing.seller], listingId);

        // Remove from active listings
        s_activeListings[listing.contractAddress][listing.tokenId][listing.seller] = bytes32(0);
    }
}
