// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnglishAuctionImplementation} from "src/core/proxy/EnglishAuctionImplementation.sol";
import {DutchAuctionImplementation} from "src/core/proxy/DutchAuctionImplementation.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {AuctionType, AuctionCreationParams} from "src/types/AuctionTypes.sol";
import {IMarketplaceValidator} from "src/interfaces/IMarketplaceValidator.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "src/events/AuctionEvents.sol";
import "src/errors/AuctionErrors.sol";

// Import Pausable errors
error EnforcedPause();
error ExpectedPause();

/**
 * @title AuctionFactory
 * @notice Factory contract for creating and managing auction contracts
 * @dev Manages both English and Dutch auction deployments and provides unified interface
 * @author NFT Marketplace Team
 */
contract AuctionFactory is Ownable, Pausable, ReentrancyGuard {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice English auction implementation contract
    address public englishAuctionImplementation;

    /// @notice Dutch auction implementation contract
    address public dutchAuctionImplementation;

    /// @notice Marketplace wallet for fee collection
    address public marketplaceWallet;

    /// @notice Marketplace validator for cross-validation
    IMarketplaceValidator public marketplaceValidator;

    /// @notice Mapping to track all created auctions across both types
    mapping(bytes32 => address) public auctionToContract;

    /// @notice Array of all auction IDs
    bytes32[] public allAuctionIds;

    /// @notice Mapping from user to their auction IDs
    mapping(address => bytes32[]) public userAuctions;

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Struct for Dutch auction specific parameters
    struct DutchAuctionParams {
        AuctionCreationParams baseParams;
        uint256 priceDropPerHour;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event AuctionImplementationsDeployed(
        address indexed englishAuctionImplementation,
        address indexed dutchAuctionImplementation,
        address indexed marketplaceWallet
    );

    event AuctionCreatedViaFactory(
        bytes32 indexed auctionId,
        address indexed auctionContract,
        address indexed seller,
        AuctionType auctionType
    );

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the auction factory
     * @param _marketplaceWallet Address to receive marketplace fees
     * @param _englishAuctionImpl Pre-deployed EnglishAuctionImplementation address
     * @param _dutchAuctionImpl Pre-deployed DutchAuctionImplementation address
     */
    constructor(
        address _marketplaceWallet,
        address _englishAuctionImpl,
        address _dutchAuctionImpl
    ) Ownable(msg.sender) {
        _validateMarketplaceWallet(_marketplaceWallet);
        require(_englishAuctionImpl != address(0), "Invalid english auction impl");
        require(_dutchAuctionImpl != address(0), "Invalid dutch auction impl");
        
        marketplaceWallet = _marketplaceWallet;
        englishAuctionImplementation = _englishAuctionImpl;
        dutchAuctionImplementation = _dutchAuctionImpl;

        emit AuctionImplementationsDeployed(
            _englishAuctionImpl, _dutchAuctionImpl, _marketplaceWallet
        );
    }

    // ============================================================================
    // AUCTION CREATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates a new English auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @return auctionId Unique identifier for the created auction
     */
    function createEnglishAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (bytes32 auctionId) {
        AuctionCreationParams memory params = AuctionCreationParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            auctionType: AuctionType.ENGLISH,
            seller: msg.sender,
            bidIncrement: 500, // Default 5%
            extendOnBid: false
        });

        // Validate NFT availability before creating auction
        _validateNFTAvailability(params.nftContract, params.tokenId, params.seller);

        return _createEnglishAuctionInternal(params);
    }

    /**
     * @notice Creates a new Dutch auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param amount Amount to auction (1 for ERC721)
     * @param startPrice Starting price for the auction
     * @param reservePrice Reserve price (minimum acceptable price)
     * @param duration Auction duration in seconds
     * @param priceDropPerHour Price drop percentage per hour (in basis points)
     * @return auctionId Unique identifier for the created auction
     */
    function createDutchAuction(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 priceDropPerHour
    ) external whenNotPaused nonReentrant returns (bytes32 auctionId) {
        DutchAuctionParams memory params = DutchAuctionParams({
            baseParams: AuctionCreationParams({
                nftContract: nftContract,
                tokenId: tokenId,
                amount: amount,
                startPrice: startPrice,
                reservePrice: reservePrice,
                duration: duration,
                auctionType: AuctionType.DUTCH,
                seller: msg.sender,
                bidIncrement: 0, // Not used in Dutch auction
                extendOnBid: false
            }),
            priceDropPerHour: priceDropPerHour
        });

        // Validate NFT availability before creating auction
        _validateNFTAvailability(params.baseParams.nftContract, params.baseParams.tokenId, params.baseParams.seller);

        return _createDutchAuctionInternal(params);
    }

    // ============================================================================
    // BATCH AUCTION CREATION FUNCTIONS
    // ============================================================================

    /// @notice Struct for batch English auction parameters
    struct BatchEnglishParams {
        address nftContract;
        uint256 startPrice;
        uint256 reservePrice;
        uint256 duration;
    }

    /**
     * @notice Creates multiple English auctions in a single transaction
     * @param nftContract Address of the NFT contract (same for all)
     * @param tokenIds Array of token IDs to auction
     * @param amounts Array of amounts to auction (1 for ERC721)
     * @param startPrice Starting price for all auctions
     * @param reservePrice Reserve price for all auctions
     * @param duration Auction duration in seconds for all auctions
     * @return auctionIds Array of unique identifiers for the created auctions
     */
    function batchCreateEnglishAuction(
        address nftContract,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (bytes32[] memory auctionIds) {
        uint256 length = tokenIds.length;
        require(length > 0, "Empty array");
        require(length == amounts.length, "Array length mismatch");
        require(length <= 20, "Max 20 auctions per batch");

        // Validate all NFTs first
        for (uint256 i = 0; i < length; i++) {
            _validateNFTAvailability(nftContract, tokenIds[i], msg.sender);
        }

        BatchEnglishParams memory batchParams = BatchEnglishParams({
            nftContract: nftContract,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration
        });

        auctionIds = _batchCreateEnglishInternal(batchParams, tokenIds, amounts);
        return auctionIds;
    }

    /**
     * @notice Internal function for batch English auction creation
     */
    function _batchCreateEnglishInternal(
        BatchEnglishParams memory batchParams,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) internal returns (bytes32[] memory auctionIds) {
        uint256 length = tokenIds.length;
        auctionIds = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            AuctionCreationParams memory params = AuctionCreationParams({
                nftContract: batchParams.nftContract,
                tokenId: tokenIds[i],
                amount: amounts[i],
                startPrice: batchParams.startPrice,
                reservePrice: batchParams.reservePrice,
                duration: batchParams.duration,
                auctionType: AuctionType.ENGLISH,
                seller: msg.sender,
                bidIncrement: 500,
                extendOnBid: false
            });

            auctionIds[i] = _createEnglishAuctionInternal(params);
        }

        return auctionIds;
    }

    /// @notice Struct for batch Dutch auction parameters
    struct BatchDutchParams {
        address nftContract;
        uint256 startPrice;
        uint256 reservePrice;
        uint256 duration;
        uint256 priceDropPerHour;
    }

    /**
     * @notice Creates multiple Dutch auctions in a single transaction
     * @param nftContract Address of the NFT contract (same for all)
     * @param tokenIds Array of token IDs to auction
     * @param amounts Array of amounts to auction (1 for ERC721)
     * @param startPrice Starting price for all auctions
     * @param reservePrice Reserve price for all auctions
     * @param duration Auction duration in seconds for all auctions
     * @param priceDropPerHour Price drop percentage per hour (in basis points)
     * @return auctionIds Array of unique identifiers for the created auctions
     */
    function batchCreateDutchAuction(
        address nftContract,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 priceDropPerHour
    ) external whenNotPaused nonReentrant returns (bytes32[] memory auctionIds) {
        uint256 length = tokenIds.length;
        require(length > 0, "Empty array");
        require(length == amounts.length, "Array length mismatch");
        require(length <= 20, "Max 20 auctions per batch");

        // Validate all NFTs first
        for (uint256 i = 0; i < length; i++) {
            _validateNFTAvailability(nftContract, tokenIds[i], msg.sender);
        }

        BatchDutchParams memory batchParams = BatchDutchParams({
            nftContract: nftContract,
            startPrice: startPrice,
            reservePrice: reservePrice,
            duration: duration,
            priceDropPerHour: priceDropPerHour
        });

        auctionIds = _batchCreateDutchInternal(batchParams, tokenIds, amounts);
        return auctionIds;
    }

    /**
     * @notice Internal function for batch Dutch auction creation
     */
    function _batchCreateDutchInternal(
        BatchDutchParams memory batchParams,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) internal returns (bytes32[] memory auctionIds) {
        uint256 length = tokenIds.length;
        auctionIds = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            DutchAuctionParams memory params = DutchAuctionParams({
                baseParams: AuctionCreationParams({
                    nftContract: batchParams.nftContract,
                    tokenId: tokenIds[i],
                    amount: amounts[i],
                    startPrice: batchParams.startPrice,
                    reservePrice: batchParams.reservePrice,
                    duration: batchParams.duration,
                    auctionType: AuctionType.DUTCH,
                    seller: msg.sender,
                    bidIncrement: 0,
                    extendOnBid: false
                }),
                priceDropPerHour: batchParams.priceDropPerHour
            });

            auctionIds[i] = _createDutchAuctionInternal(params);
        }

        return auctionIds;
    }

    // ============================================================================
    // AUCTION INTERACTION FUNCTIONS
    // ============================================================================

    /**
     * @notice Places a bid in an English auction
     * @param auctionId Unique identifier of the auction
     */
    function placeBid(bytes32 auctionId) external payable nonReentrant whenNotPaused {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        IAuction(auctionContract).placeBidFor{value: msg.value}(auctionId, msg.sender);
    }

    /**
     * @notice Purchases NFT in a Dutch auction
     * @param auctionId Unique identifier of the auction
     */
    function buyNow(bytes32 auctionId) external payable nonReentrant whenNotPaused {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        IAuction(auctionContract).buyNowFor{value: msg.value}(auctionId, msg.sender);
    }

    /**
     * @notice Cancels an auction
     * @param auctionId Unique identifier of the auction
     */
    function cancelAuction(bytes32 auctionId) external nonReentrant whenNotPaused {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        // Get auction details to validate seller
        IAuction.Auction memory auction = IAuction(auctionContract).getAuction(auctionId);
        if (auction.seller != msg.sender) {
            revert Auction__NotAuctionSeller();
        }

        // Delegate cancellation to the underlying auction contract. For English auctions
        // with existing bids, the contract will handle refunding all bidders.
        // This bypasses the onlySeller modifier since seller was validated above.
        IAuction(auctionContract).cancelAuctionFor(auctionId, msg.sender);

        // Notify validator about auction cancellation
        _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);
    }

    /**
     * @notice Cancels multiple auctions in a single transaction
     * @param auctionIds Array of auction IDs to cancel
     * @return cancelledCount Number of auctions successfully cancelled
     * @dev Only auctions owned by msg.sender will be cancelled, others are skipped
     */
    function batchCancelAuction(bytes32[] calldata auctionIds) external nonReentrant whenNotPaused returns (uint256 cancelledCount) {
        uint256 length = auctionIds.length;
        require(length > 0, "Empty array");
        require(length <= 20, "Max 20 cancellations per batch");

        for (uint256 i = 0; i < length; i++) {
            bytes32 auctionId = auctionIds[i];
            address auctionContract = auctionToContract[auctionId];
            
            // Skip if auction doesn't exist
            if (auctionContract == address(0)) {
                continue;
            }

            // Get auction details
            IAuction.Auction memory auction = IAuction(auctionContract).getAuction(auctionId);
            
            // Skip if not the seller
            if (auction.seller != msg.sender) {
                continue;
            }

            // Try to cancel, skip on failure (e.g., auction already ended)
            try IAuction(auctionContract).cancelAuctionFor(auctionId, msg.sender) {
                _notifyValidatorAuctionCancelled(auction.nftContract, auction.tokenId, auction.seller);
                cancelledCount++;
            } catch {
                // Skip failed cancellations
                continue;
            }
        }

        return cancelledCount;
    }

    /**
     * @notice Settles a completed auction
     * @param auctionId Unique identifier of the auction
     */
    function settleAuction(bytes32 auctionId) external nonReentrant whenNotPaused {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        IAuction(auctionContract).settleAuction(auctionId);
    }

    /**
     * @notice Withdraws a refunded bid
     * @param auctionId Unique identifier of the auction
     */
    function withdrawBid(bytes32 auctionId) external nonReentrant whenNotPaused {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        IAuction(auctionContract).withdrawBidFor(auctionId, msg.sender);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets auction details
     * @param auctionId Unique identifier of the auction
     * @return auction Auction struct with all details
     */
    function getAuction(bytes32 auctionId) external view returns (IAuction.Auction memory auction) {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        return IAuction(auctionContract).getAuction(auctionId);
    }

    /**
     * @notice Gets current price for an auction
     * @param auctionId Unique identifier of the auction
     * @return currentPrice Current price of the auction
     */
    function getCurrentPrice(bytes32 auctionId) external view returns (uint256 currentPrice) {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        return IAuction(auctionContract).getCurrentPrice(auctionId);
    }

    /**
     * @notice Checks if an auction is active
     * @param auctionId Unique identifier of the auction
     * @return isActive Whether the auction is currently active
     */
    function isAuctionActive(bytes32 auctionId) external view returns (bool isActive) {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            return false;
        }

        return IAuction(auctionContract).isAuctionActive(auctionId);
    }

    /**
     * @notice Gets all auction IDs
     * @return auctionIds Array of all auction IDs
     */
    function getAllAuctions() external view returns (bytes32[] memory auctionIds) {
        return allAuctionIds;
    }

    /**
     * @notice Gets auctions created by a specific user
     * @param user Address of the user
     * @return auctionIds Array of auction IDs created by the user
     */
    function getUserAuctions(address user) external view returns (bytes32[] memory auctionIds) {
        return userAuctions[user];
    }

    /**
     * @notice Gets the contract address for a specific auction
     * @param auctionId Unique identifier of the auction
     * @return contractAddress Address of the auction contract
     */
    function getAuctionContract(bytes32 auctionId) external view returns (address contractAddress) {
        return auctionToContract[auctionId];
    }

    // ============================================================================
    // BACKWARD COMPATIBILITY FUNCTIONS (DEPRECATED)
    // ============================================================================

    /**
     * @notice Gets English auction implementation as contract type
     * @dev DEPRECATED: Use englishAuctionImplementation instead
     * @return implementation English auction implementation contract
     */
    function englishAuction() external view returns (EnglishAuctionImplementation implementation) {
        return EnglishAuctionImplementation(englishAuctionImplementation);
    }

    /**
     * @notice Gets Dutch auction implementation as contract type
     * @dev DEPRECATED: Use dutchAuctionImplementation instead
     * @return implementation Dutch auction implementation contract
     */
    function dutchAuction() external view returns (DutchAuctionImplementation implementation) {
        return DutchAuctionImplementation(dutchAuctionImplementation);
    }

    /**
     * @notice Gets pending refund amount for a bidder
     * @param auctionId Unique identifier of the auction
     * @param bidder Address of the bidder
     * @return refundAmount Amount available for refund
     */
    function getPendingRefund(bytes32 auctionId, address bidder) external view returns (uint256 refundAmount) {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            return 0;
        }

        return IAuction(auctionContract).getPendingRefund(auctionId, bidder);
    }

    /**
     * @notice Gets time to reserve price for Dutch auctions
     * @param auctionId Unique identifier of the auction
     * @return timeToReserve Time in seconds until reserve price is reached
     */
    function getTimeToReservePrice(bytes32 auctionId) external view returns (uint256) {
        address auctionContract = auctionToContract[auctionId];
        if (auctionContract == address(0)) {
            revert Auction__AuctionNotFound();
        }

        // Check if this is a Dutch auction by trying to call the method
        try DutchAuctionImplementation(auctionContract).getTimeToReservePrice(auctionId) returns (uint256 timeToReserve)
        {
            return timeToReserve;
        } catch {
            revert Auction__UnsupportedAuctionType();
        }
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Pauses/unpauses the factory
     * @param paused Whether to pause or unpause
     */
    function setPaused(bool paused) external onlyOwner {
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

        // Note: Individual auction proxies need to be paused separately
        // as they are independent contracts

        emit AuctionFactoryPaused(paused, msg.sender);
    }

    /**
     * @notice Updates marketplace wallet
     * @param newWallet New marketplace wallet address
     */
    function setMarketplaceWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) {
            revert Auction__ZeroAddress();
        }

        marketplaceWallet = newWallet;

        // Note: Individual auction proxies need to be updated separately
        // as they are independent contracts
    }

    /**
     * @notice Sets marketplace validator for both auction contracts
     * @param validator Address of the marketplace validator contract
     */
    function setMarketplaceValidator(address validator) external onlyOwner {
        marketplaceValidator = IMarketplaceValidator(validator);
    }

    /**
     * @notice Transfers NFT from seller to buyer on behalf of auction contracts
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to transfer
     * @param amount Amount to transfer (1 for ERC721)
     * @param from Address to transfer from (seller)
     * @param to Address to transfer to (buyer)
     * @dev Only callable by registered auction contracts
     */
    function transferNFTFromSeller(address nftContract, uint256 tokenId, uint256 amount, address from, address to)
        external
    {
        // Verify caller is a registered auction contract
        bool isValidCaller = false;
        for (uint256 i = 0; i < allAuctionIds.length; i++) {
            if (auctionToContract[allAuctionIds[i]] == msg.sender) {
                isValidCaller = true;
                break;
            }
        }
        require(isValidCaller, "Unauthorized caller");

        // Auto-detect NFT standard and transfer
        try IERC721(nftContract).supportsInterface(0x80ac58cd) returns (bool isERC721) {
            if (isERC721) {
                IERC721(nftContract).transferFrom(from, to, tokenId);
            } else {
                IERC1155(nftContract).safeTransferFrom(from, to, tokenId, amount, "");
            }
        } catch {
            revert Auction__NFTTransferFailed();
        }
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Internal function to create English auction with proxy
     * @param params Auction creation parameters
     * @return auctionId The created auction ID
     */
    function _createEnglishAuctionInternal(AuctionCreationParams memory params) internal returns (bytes32 auctionId) {
        address auctionProxy = _deployAuctionProxy(AuctionType.ENGLISH);
        auctionId = _initializeAuction(auctionProxy, params, AuctionType.ENGLISH);
        _registerAuction(auctionId, auctionProxy, AuctionType.ENGLISH);
        return auctionId;
    }

    /**
     * @notice Internal function to create Dutch auction with proxy
     * @param params Dutch auction creation parameters
     * @return auctionId The created auction ID
     */
    function _createDutchAuctionInternal(DutchAuctionParams memory params) internal returns (bytes32 auctionId) {
        address auctionProxy = _deployAuctionProxy(AuctionType.DUTCH);
        auctionId = _initializeDutchAuction(auctionProxy, params);
        _registerAuction(auctionId, auctionProxy, AuctionType.DUTCH);
        return auctionId;
    }

    /**
     * @notice Deploys auction proxy based on type
     * @param auctionType Type of auction to deploy
     * @return proxyAddress Address of deployed proxy
     */
    function _deployAuctionProxy(AuctionType auctionType) internal returns (address proxyAddress) {
        if (auctionType == AuctionType.ENGLISH) {
            proxyAddress = Clones.clone(englishAuctionImplementation);
        } else if (auctionType == AuctionType.DUTCH) {
            proxyAddress = Clones.clone(dutchAuctionImplementation);
        } else {
            revert Auction__UnsupportedAuctionType();
        }
    }

    /**
     * @notice Initializes auction proxy
     * @param proxyAddress Address of the proxy
     * @param params Auction creation parameters
     * @param auctionType Type of auction
     * @return auctionId The created auction ID
     */
    function _initializeAuction(
        address proxyAddress,
        AuctionCreationParams memory params,
        AuctionType auctionType
    ) internal returns (bytes32 auctionId) {
        EnglishAuctionImplementation(proxyAddress).initialize(marketplaceWallet);

        auctionId = IAuction(proxyAddress).createAuction(
            params.nftContract,
            params.tokenId,
            params.amount,
            params.startPrice,
            params.reservePrice,
            params.duration,
            auctionType,
            params.seller
        );
    }

    /**
     * @notice Initializes Dutch auction proxy
     * @param proxyAddress Address of the proxy
     * @param params Dutch auction creation parameters
     * @return auctionId The created auction ID
     */
    function _initializeDutchAuction(address proxyAddress, DutchAuctionParams memory params)
        internal
        returns (bytes32 auctionId)
    {
        DutchAuctionImplementation(proxyAddress).initialize(marketplaceWallet);

        auctionId = DutchAuctionImplementation(proxyAddress).createDutchAuction(
            params.baseParams.nftContract,
            params.baseParams.tokenId,
            params.baseParams.amount,
            params.baseParams.startPrice,
            params.baseParams.reservePrice,
            params.baseParams.duration,
            params.priceDropPerHour,
            params.baseParams.seller
        );
    }

    /**
     * @notice Registers a new auction in factory mappings
     * @param auctionId The auction ID
     * @param auctionContract The auction contract address
     * @param auctionType The type of auction
     */
    function _registerAuction(bytes32 auctionId, address auctionContract, AuctionType auctionType) internal {
        auctionToContract[auctionId] = auctionContract;
        allAuctionIds.push(auctionId);
        userAuctions[msg.sender].push(auctionId);

        // Notify validator about auction creation
        _notifyValidatorAuctionCreated(auctionId, auctionContract);

        emit AuctionCreatedViaFactory(auctionId, auctionContract, msg.sender, auctionType);
    }

    /**
     * @notice Validates marketplace wallet address
     * @param _marketplaceWallet Address to validate
     */
    function _validateMarketplaceWallet(address _marketplaceWallet) internal pure {
        if (_marketplaceWallet == address(0)) {
            revert Auction__ZeroAddress();
        }
    }



    /**
     * @notice Validates NFT availability for auction (not already listed)
     */
    function _validateNFTAvailability(address nftContract, uint256 tokenId, address seller) internal view {
        // Skip validation if validator is not set
        if (address(marketplaceValidator) == address(0)) {
            return;
        }

        // Check if NFT is available for auction
        (bool isAvailable, IMarketplaceValidator.NFTStatus status) =
            marketplaceValidator.isNFTAvailable(nftContract, tokenId, seller);

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
     * @notice Notifies validator about auction creation
     */
    function _notifyValidatorAuctionCreated(bytes32 auctionId, address auctionContract) internal {
        if (address(marketplaceValidator) != address(0)) {
            // Get auction details to notify validator
            IAuction.Auction memory auction = IAuction(auctionContract).getAuction(auctionId);

            try marketplaceValidator.setNFTInAuction(auction.nftContract, auction.tokenId, auction.seller, auctionId) {}
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
}
