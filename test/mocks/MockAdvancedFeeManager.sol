// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockAdvancedFeeManager
 * @notice Mock fee manager contract for testing
 * @dev Provides configurable platform and royalty fees
 */
contract MockAdvancedFeeManager is Ownable {
    address public feeRecipient;
    uint256 public platformFeePercentage = 250; // 2.5%
    uint256 public royaltyFeePercentage = 500; // 5%

    // Mapping for collection-specific royalty recipients
    mapping(address => address) public collectionRoyaltyRecipients;
    mapping(address => uint256) public collectionRoyaltyPercentages;

    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event RoyaltyFeeUpdated(uint256 oldFee, uint256 newFee);
    event CollectionRoyaltySet(address indexed collection, address recipient, uint256 percentage);

    constructor(address _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Calculates platform and royalty fees
     * @param price Sale price
     * @param collection Collection address
     * @return platformFee Platform fee amount
     * @return royaltyFee Royalty fee amount
     */
    function calculateFees(
        uint256 price,
        address collection,
        uint256 /* tokenId */
    )
        external
        view
        returns (uint256 platformFee, uint256 royaltyFee)
    {
        platformFee = (price * platformFeePercentage) / 10000;

        // Check for collection-specific royalty
        if (collectionRoyaltyRecipients[collection] != address(0)) {
            royaltyFee = (price * collectionRoyaltyPercentages[collection]) / 10000;
        } else {
            royaltyFee = (price * royaltyFeePercentage) / 10000;
        }
    }

    /**
     * @notice Gets the fee recipient address
     * @return Fee recipient address
     */
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }

    /**
     * @notice Gets royalty recipient for a collection
     * @param collection Collection address
     * @return Royalty recipient address
     */
    function getRoyaltyRecipient(address collection) external view returns (address) {
        address recipient = collectionRoyaltyRecipients[collection];
        return recipient != address(0) ? recipient : feeRecipient;
    }

    /**
     * @notice Sets the fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0));
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    /**
     * @notice Sets the platform fee percentage
     * @param _platformFeePercentage New platform fee percentage in basis points
     */
    function setPlatformFeePercentage(uint256 _platformFeePercentage) external onlyOwner {
        require(_platformFeePercentage <= 1000); // Max 10%
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = _platformFeePercentage;
        emit PlatformFeeUpdated(oldFee, _platformFeePercentage);
    }

    /**
     * @notice Sets the default royalty fee percentage
     * @param _royaltyFeePercentage New royalty fee percentage in basis points
     */
    function setRoyaltyFeePercentage(uint256 _royaltyFeePercentage) external onlyOwner {
        require(_royaltyFeePercentage <= 1000); // Max 10%
        uint256 oldFee = royaltyFeePercentage;
        royaltyFeePercentage = _royaltyFeePercentage;
        emit RoyaltyFeeUpdated(oldFee, _royaltyFeePercentage);
    }

    /**
     * @notice Sets collection-specific royalty info
     * @param collection Collection address
     * @param recipient Royalty recipient
     * @param percentage Royalty percentage in basis points
     */
    function setCollectionRoyalty(address collection, address recipient, uint256 percentage) external onlyOwner {
        require(collection != address(0));
        require(recipient != address(0));
        require(percentage <= 1000); // Max 10%

        collectionRoyaltyRecipients[collection] = recipient;
        collectionRoyaltyPercentages[collection] = percentage;
        emit CollectionRoyaltySet(collection, recipient, percentage);
    }

    /**
     * @notice Removes collection-specific royalty info
     * @param collection Collection address
     */
    function removeCollectionRoyalty(address collection) external onlyOwner {
        delete collectionRoyaltyRecipients[collection];
        delete collectionRoyaltyPercentages[collection];
        emit CollectionRoyaltySet(collection, address(0), 0);
    }
}
