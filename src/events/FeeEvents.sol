// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title FeeEvents
 * @notice Contains all events related to fee management
 * @dev Centralized event definitions for better organization and maintenance
 */

// ============================================================================
// FEE MANAGEMENT EVENTS
// ============================================================================

/**
 * @notice Emitted when a fee is updated
 * @param feeType Type of fee being updated (e.g., "marketplace", "royalty", "taker")
 * @param oldValue Previous fee value
 * @param newValue New fee value
 * @param updatedBy Address that updated the fee
 * @param timestamp When the fee was updated
 */
event FeeUpdated(
    string indexed feeType, uint256 oldValue, uint256 newValue, address indexed updatedBy, uint256 timestamp
);
