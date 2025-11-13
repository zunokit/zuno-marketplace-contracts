// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NFTValidationLib} from "./NFTValidationLib.sol";
import {PaymentDistributionLib} from "./PaymentDistributionLib.sol";
import {RoyaltyLib} from "./RoyaltyLib.sol";

/**
 * @title BatchOperationsLib
 * @notice Library for handling batch operations in NFT marketplace
 * @dev Centralizes batch listing and buying logic to reduce code duplication
 */
library BatchOperationsLib {
    // ============================================================================
    // ERRORS
    // ============================================================================

    error BatchOperations__ArrayLengthMismatch();
    error BatchOperations__EmptyArray();
    error BatchOperations__ValidationFailed(uint256 index, string reason);
    error BatchOperations__InsufficientPayment();
    error BatchOperations__DifferentCollections();

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Batch listing parameters
     */
    struct BatchListingParams {
        address nftContract;
        uint256[] tokenIds;
        uint256[] amounts; // For ERC1155, use 1 for ERC721
        uint256[] prices;
        uint256 listingDuration;
        address seller;
        address spender; // marketplace contract
    }

    /**
     * @notice Batch purchase parameters
     */
    struct BatchPurchaseParams {
        bytes32[] listingIds;
        address buyer;
        uint256 totalPayment;
        uint256 takerFeeRate;
        uint256 bpsDenominator;
    }

    /**
     * @notice Individual listing data for batch operations
     */
    struct ListingData {
        address contractAddress;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        address seller;
        bool isValid;
        string errorMessage;
    }

    /**
     * @notice Purchase calculation result
     */
    struct PurchaseCalculation {
        uint256 totalPrice;
        uint256 totalMarketplaceFee;
        uint256 totalRoyalty;
        bool isValid;
        string errorMessage;
    }

    // ============================================================================
    // BATCH VALIDATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates batch listing parameters
     * @param params Batch listing parameters
     * @return isValid True if all validations pass
     * @return errorMessage Error message if validation fails
     */
    function validateBatchListing(BatchListingParams memory params)
        internal
        view
        returns (bool isValid, string memory errorMessage)
    {
        // Check array lengths
        if (params.tokenIds.length != params.prices.length || params.tokenIds.length != params.amounts.length) {
            return (false, "Array length mismatch");
        }

        if (params.tokenIds.length == 0) {
            return (false, "Empty arrays");
        }

        if (params.listingDuration == 0) {
            return (false, "Invalid listing duration");
        }

        // Validate each NFT
        for (uint256 i = 0; i < params.tokenIds.length; i++) {
            if (params.prices[i] == 0) {
                return (false, "Zero price not allowed");
            }

            if (params.amounts[i] == 0) {
                return (false, "Zero amount not allowed");
            }

            // Validate NFT ownership and approval
            NFTValidationLib.ValidationParams memory validationParams = NFTValidationLib.createValidationParams(
                params.nftContract, params.tokenIds[i], params.amounts[i], params.seller, params.spender
            );

            NFTValidationLib.ValidationResult memory result = NFTValidationLib.validateNFT(validationParams);
            if (!result.isValid) {
                return (false, string(abi.encodePacked("Token ", _toString(i), ": ", result.errorMessage)));
            }
        }

        return (true, "");
    }

    /**
     * @notice Validates batch purchase parameters
     * @param params Batch purchase parameters
     * @param listings Array of listing data
     * @return calculation Purchase calculation result
     */
    function validateAndCalculateBatchPurchase(BatchPurchaseParams memory params, ListingData[] memory listings)
        internal
        view
        returns (PurchaseCalculation memory calculation)
    {
        if (params.listingIds.length == 0) {
            calculation.errorMessage = "Empty listing array";
            return calculation;
        }

        if (params.listingIds.length != listings.length) {
            calculation.errorMessage = "Array length mismatch";
            return calculation;
        }

        // Validate all listings are from same collection
        address firstCollection = listings[0].contractAddress;
        for (uint256 i = 1; i < listings.length; i++) {
            if (listings[i].contractAddress != firstCollection) {
                calculation.errorMessage = "Different collections not allowed";
                return calculation;
            }
        }

        // Calculate total costs
        uint256 totalPrice = 0;
        uint256 totalMarketplaceFee = 0;
        uint256 totalRoyalty = 0;

        for (uint256 i = 0; i < listings.length; i++) {
            if (!listings[i].isValid) {
                calculation.errorMessage = string(abi.encodePacked("Invalid listing at index ", _toString(i)));
                return calculation;
            }

            // Calculate fees for this listing
            (address royaltyReceiver, uint256 royaltyAmount) =
                RoyaltyLib.calculateRoyalty(listings[i].contractAddress, listings[i].tokenId, listings[i].price);

            uint256 marketplaceFee = PaymentDistributionLib.calculatePercentage(
                listings[i].price, params.takerFeeRate, params.bpsDenominator
            );

            totalPrice += listings[i].price;
            totalMarketplaceFee += marketplaceFee;
            totalRoyalty += royaltyAmount;
        }

        uint256 totalRequired = totalPrice + totalMarketplaceFee + totalRoyalty;
        if (params.totalPayment < totalRequired) {
            calculation.errorMessage = "Insufficient payment";
            return calculation;
        }

        calculation.totalPrice = totalPrice;
        calculation.totalMarketplaceFee = totalMarketplaceFee;
        calculation.totalRoyalty = totalRoyalty;
        calculation.isValid = true;
        return calculation;
    }

    // ============================================================================
    // BATCH PROCESSING FUNCTIONS
    // ============================================================================

    /**
     * @notice Processes batch listing creation
     * @param params Batch listing parameters
     * @return listingIds Array of generated listing IDs
     */
    function processBatchListing(BatchListingParams memory params) internal view returns (bytes32[] memory listingIds) {
        listingIds = new bytes32[](params.tokenIds.length);

        for (uint256 i = 0; i < params.tokenIds.length; i++) {
            listingIds[i] = generateListingId(
                params.nftContract,
                params.tokenIds[i],
                params.seller,
                block.timestamp + i // Add index to ensure uniqueness
            );
        }

        return listingIds;
    }

    /**
     * @notice Calculates individual purchase data for batch operations
     * @param listing Listing data
     * @param takerFeeRate Taker fee rate in basis points
     * @param bpsDenominator Basis points denominator
     * @return paymentData Payment distribution data
     */
    function calculateIndividualPurchase(ListingData memory listing, uint256 takerFeeRate, uint256 bpsDenominator)
        internal
        view
        returns (PaymentDistributionLib.PaymentData memory paymentData)
    {
        (address royaltyReceiver, uint256 royaltyAmount) =
            RoyaltyLib.calculateRoyalty(listing.contractAddress, listing.tokenId, listing.price);

        uint256 marketplaceFee = PaymentDistributionLib.calculatePercentage(listing.price, takerFeeRate, bpsDenominator);

        uint256 totalAmount = listing.price + marketplaceFee + royaltyAmount;

        return PaymentDistributionLib.PaymentData({
            seller: listing.seller,
            royaltyReceiver: royaltyReceiver,
            marketplaceWallet: address(0), // Will be set by calling contract
            totalAmount: totalAmount,
            sellerAmount: listing.price,
            marketplaceFee: marketplaceFee,
            royaltyAmount: royaltyAmount
        });
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Generates a unique listing ID
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param seller Seller address
     * @param timestamp Timestamp for uniqueness
     * @return listingId Generated listing ID
     */
    function generateListingId(address nftContract, uint256 tokenId, address seller, uint256 timestamp)
        internal
        pure
        returns (bytes32 listingId)
    {
        return keccak256(abi.encodePacked(nftContract, tokenId, seller, timestamp));
    }

    /**
     * @notice Creates listing data struct
     * @param contractAddress NFT contract address
     * @param tokenId Token ID
     * @param amount Amount (1 for ERC721)
     * @param price Price
     * @param seller Seller address
     * @return listingData Listing data struct
     */
    function createListingData(address contractAddress, uint256 tokenId, uint256 amount, uint256 price, address seller)
        internal
        pure
        returns (ListingData memory listingData)
    {
        return ListingData({
            contractAddress: contractAddress,
            tokenId: tokenId,
            amount: amount,
            price: price,
            seller: seller,
            isValid: true,
            errorMessage: ""
        });
    }

    /**
     * @notice Converts uint256 to string
     * @param value Value to convert
     * @return String representation
     */
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Validates that all listings belong to the same collection
     * @param listings Array of listing data
     * @return isValid True if all from same collection
     * @return collection The collection address (if valid)
     */
    function validateSameCollection(ListingData[] memory listings)
        internal
        pure
        returns (bool isValid, address collection)
    {
        if (listings.length == 0) {
            return (false, address(0));
        }

        collection = listings[0].contractAddress;
        for (uint256 i = 1; i < listings.length; i++) {
            if (listings[i].contractAddress != collection) {
                return (false, address(0));
            }
        }
        return (true, collection);
    }
}
