// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title OfferEscrowManager
 * @notice Manages escrow of payments for marketplace offers
 * @dev Handles both ETH and ERC20 token escrow operations
 */
contract OfferEscrowManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================================================
    // ERRORS
    // ============================================================================

    error Escrow__InsufficientBalance();
    error Escrow__InvalidAmount();
    error Escrow__TransferFailed();
    error Escrow__Unauthorized();
    error Escrow__InvalidOfferId();

    // ============================================================================
    // EVENTS
    // ============================================================================

    event FundsLocked(bytes32 indexed offerId, address indexed offerer, address paymentToken, uint256 amount);
    event FundsReleased(bytes32 indexed offerId, address indexed recipient, address paymentToken, uint256 amount);
    event FundsRefunded(bytes32 indexed offerId, address indexed offerer, address paymentToken, uint256 amount);

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Tracks escrowed ETH amounts per offer
    mapping(bytes32 => uint256) public escrowedETH;

    /// @notice Tracks escrowed ERC20 amounts per offer per token
    mapping(bytes32 => mapping(address => uint256)) public escrowedERC20;

    /// @notice Tracks offer owners
    mapping(bytes32 => address) public offerOwners;

    /// @notice Authorized callers (OfferManager, etc.)
    mapping(address => bool) public authorizedCallers;

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender]) {
            revert Escrow__Unauthorized();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    constructor() Ownable(msg.sender) {}

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Authorizes a caller to use escrow functions
     * @param caller Address to authorize
     */
    function authorizeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
    }

    /**
     * @notice Revokes authorization for a caller
     * @param caller Address to revoke
     */
    function revokeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
    }

    // ============================================================================
    // ESCROW FUNCTIONS - ETH
    // ============================================================================

    /**
     * @notice Locks ETH payment for an offer
     * @param offerId Unique offer identifier
     * @param offerer Address of the offerer
     */
    function lockETH(bytes32 offerId, address offerer) external payable onlyAuthorized nonReentrant {
        if (msg.value == 0) {
            revert Escrow__InvalidAmount();
        }

        escrowedETH[offerId] += msg.value;
        offerOwners[offerId] = offerer;

        emit FundsLocked(offerId, offerer, address(0), msg.value);
    }

    /**
     * @notice Releases escrowed ETH to recipient
     * @param offerId Unique offer identifier
     * @param recipient Address to receive the funds
     * @param amount Amount to release
     */
    function releaseETH(bytes32 offerId, address recipient, uint256 amount) external onlyAuthorized nonReentrant {
        if (escrowedETH[offerId] < amount) {
            revert Escrow__InsufficientBalance();
        }

        escrowedETH[offerId] -= amount;

        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert Escrow__TransferFailed();
        }

        emit FundsReleased(offerId, recipient, address(0), amount);
    }

    /**
     * @notice Refunds escrowed ETH to offerer
     * @param offerId Unique offer identifier
     * @param amount Amount to refund
     */
    function refundETH(bytes32 offerId, uint256 amount) external onlyAuthorized nonReentrant {
        address offerer = offerOwners[offerId];
        if (offerer == address(0)) {
            revert Escrow__InvalidOfferId();
        }

        if (escrowedETH[offerId] < amount) {
            revert Escrow__InsufficientBalance();
        }

        escrowedETH[offerId] -= amount;

        (bool success,) = payable(offerer).call{value: amount}("");
        if (!success) {
            revert Escrow__TransferFailed();
        }

        emit FundsRefunded(offerId, offerer, address(0), amount);
    }

    // ============================================================================
    // ESCROW FUNCTIONS - ERC20
    // ============================================================================

    /**
     * @notice Locks ERC20 payment for an offer
     * @param offerId Unique offer identifier
     * @param offerer Address of the offerer
     * @param paymentToken ERC20 token address
     * @param amount Amount to lock
     */
    function lockERC20(bytes32 offerId, address offerer, address paymentToken, uint256 amount)
        external
        onlyAuthorized
        nonReentrant
    {
        if (amount == 0) {
            revert Escrow__InvalidAmount();
        }

        // Transfer tokens from offerer to this contract
        IERC20(paymentToken).safeTransferFrom(offerer, address(this), amount);

        escrowedERC20[offerId][paymentToken] += amount;
        offerOwners[offerId] = offerer;

        emit FundsLocked(offerId, offerer, paymentToken, amount);
    }

    /**
     * @notice Releases escrowed ERC20 to recipient
     * @param offerId Unique offer identifier
     * @param recipient Address to receive the tokens
     * @param paymentToken ERC20 token address
     * @param amount Amount to release
     */
    function releaseERC20(bytes32 offerId, address recipient, address paymentToken, uint256 amount)
        external
        onlyAuthorized
        nonReentrant
    {
        if (escrowedERC20[offerId][paymentToken] < amount) {
            revert Escrow__InsufficientBalance();
        }

        escrowedERC20[offerId][paymentToken] -= amount;
        IERC20(paymentToken).safeTransfer(recipient, amount);

        emit FundsReleased(offerId, recipient, paymentToken, amount);
    }

    /**
     * @notice Refunds escrowed ERC20 to offerer
     * @param offerId Unique offer identifier
     * @param paymentToken ERC20 token address
     * @param amount Amount to refund
     */
    function refundERC20(bytes32 offerId, address paymentToken, uint256 amount) external onlyAuthorized nonReentrant {
        address offerer = offerOwners[offerId];
        if (offerer == address(0)) {
            revert Escrow__InvalidOfferId();
        }

        if (escrowedERC20[offerId][paymentToken] < amount) {
            revert Escrow__InsufficientBalance();
        }

        escrowedERC20[offerId][paymentToken] -= amount;
        IERC20(paymentToken).safeTransfer(offerer, amount);

        emit FundsRefunded(offerId, offerer, paymentToken, amount);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets escrowed ETH amount for an offer
     * @param offerId Unique offer identifier
     * @return amount Escrowed ETH amount
     */
    function getEscrowedETH(bytes32 offerId) external view returns (uint256 amount) {
        return escrowedETH[offerId];
    }

    /**
     * @notice Gets escrowed ERC20 amount for an offer
     * @param offerId Unique offer identifier
     * @param paymentToken ERC20 token address
     * @return amount Escrowed token amount
     */
    function getEscrowedERC20(bytes32 offerId, address paymentToken) external view returns (uint256 amount) {
        return escrowedERC20[offerId][paymentToken];
    }

    /**
     * @notice Gets offer owner
     * @param offerId Unique offer identifier
     * @return owner Address of the offerer
     */
    function getOfferOwner(bytes32 offerId) external view returns (address owner) {
        return offerOwners[offerId];
    }
}
