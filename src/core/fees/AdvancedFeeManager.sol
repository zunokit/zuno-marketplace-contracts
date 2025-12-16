// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "src/core/access/MarketplaceAccessControl.sol";
import {FeeConfig, FeeTierConfig, FeeTier, CollectionFeeOverride, UserVolumeData, VIPStatus} from "src/types/FeeTypes.sol";
import "src/errors/FeeErrors.sol";
import "src/events/FeeEvents.sol";

/**
 * @title AdvancedFeeManager
 * @notice Manages advanced marketplace fees including maker fees, fee tiers, and collection-specific overrides
 * @dev Implements dynamic fee calculation with volume-based discounts and VIP status
 * @author NFT Marketplace Team
 */
contract AdvancedFeeManager is Ownable, ReentrancyGuard, Pausable {
    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Access control contract
    MarketplaceAccessControl public accessControl;

    /// @notice Base marketplace fee configuration
    FeeConfig public baseFeeConfig;

    /// @notice Mapping from user to their fee tier
    mapping(address => FeeTier) public userFeeTiers;

    /// @notice Mapping from collection to collection-specific fee overrides
    mapping(address => CollectionFeeOverride) public collectionFeeOverrides;

    /// @notice Mapping from user to their trading volume (for tier calculation)
    mapping(address => UserVolumeData) public userVolumeData;

    /// @notice Mapping from user to their VIP status
    mapping(address => VIPStatus) public vipStatus;

    /// @notice Fee tier thresholds and discounts
    FeeTierConfig[] public feeTierConfigs;

    /// @notice Total marketplace volume (for analytics)
    uint256 public totalMarketplaceVolume;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice Emergency fee cap (maximum fee percentage)
    uint256 public constant EMERGENCY_FEE_CAP = 1000; // 10%

    // ============================================================================
    // STRUCTS - Now imported from src/types/FeeTypes.sol
    // ============================================================================
    // Using FeeConfig, FeeTierConfig, FeeTier, CollectionFeeOverride,
    // UserVolumeData, VIPStatus from FeeTypes.sol

    // ============================================================================
    // EVENTS
    // ============================================================================

    event FeeConfigUpdated(
        uint256 oldMakerFee,
        uint256 newMakerFee,
        uint256 oldTakerFee,
        uint256 newTakerFee,
        address updatedBy
    );

    event FeeTierUpdated(
        address indexed user,
        uint256 oldTierId,
        uint256 newTierId,
        uint256 newDiscountBps
    );

    event CollectionFeeOverrideSet(
        address indexed collection,
        uint256 makerFeeOverride,
        uint256 takerFeeOverride,
        uint256 discountBps,
        bool isVerified
    );

    event VIPStatusUpdated(
        address indexed user,
        bool isVIP,
        uint256 discountBps,
        uint256 expiryTimestamp,
        string vipTier
    );

    event UserVolumeUpdated(
        address indexed user,
        uint256 newTotalVolume,
        uint256 newLast30DaysVolume,
        uint256 tradeCount
    );

    event FeesCalculated(
        address indexed user,
        address indexed collection,
        uint256 salePrice,
        uint256 finalMakerFee,
        uint256 finalTakerFee,
        uint256 totalDiscount
    );

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures caller has required role
     */
    modifier onlyRole(bytes32 role) {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert Fee__InvalidOwner();
        }
        _;
    }

    /**
     * @notice Validates fee parameters
     */
    modifier validFeeParams(uint256 makerFee, uint256 takerFee) {
        if (makerFee > EMERGENCY_FEE_CAP || takerFee > EMERGENCY_FEE_CAP) {
            revert Fee__InvalidRoyaltyFee();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the AdvancedFeeManager
     * @param _accessControl Address of the access control contract
     * @param _feeRecipient Address to receive marketplace fees
     */
    constructor(
        address _accessControl,
        address _feeRecipient
    ) Ownable(msg.sender) {
        if (_accessControl == address(0) || _feeRecipient == address(0)) {
            revert Fee__InvalidOwner();
        }

        accessControl = MarketplaceAccessControl(_accessControl);
        feeRecipient = _feeRecipient;

        // Initialize default fee configuration
        _initializeDefaultFees();
        _initializeDefaultTiers();
    }

    // ============================================================================
    // FEE CALCULATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Calculates final fees for a transaction
     * @param user Address of the user (seller for maker fee, buyer for taker fee)
     * @param collection Address of the NFT collection
     * @param salePrice Sale price of the NFT
     * @param isMaker Whether calculating maker fee (true) or taker fee (false)
     * @return finalFee The calculated fee amount
     * @return appliedDiscount The total discount applied
     */
    function calculateFees(
        address user,
        address collection,
        uint256 salePrice,
        bool isMaker
    ) external view returns (uint256 finalFee, uint256 appliedDiscount) {
        // Step 1: Calculate base fees
        uint256 baseFee = _calculateBaseFees(collection, salePrice, isMaker);

        // Step 2: Apply user-specific discounts
        uint256 userDiscount = _calculateUserDiscount(user);

        // Step 3: Apply collection-specific overrides
        (
            uint256 collectionFee,
            uint256 collectionDiscount
        ) = _applyCollectionOverride(collection, baseFee, isMaker);

        // Step 4: Apply final discount calculation
        uint256 totalDiscount = userDiscount + collectionDiscount;
        if (totalDiscount > 5000) {
            // Cap at 50% total discount
            totalDiscount = 5000;
        }

        finalFee = collectionFee - ((collectionFee * totalDiscount) / 10000);
        appliedDiscount = totalDiscount;

        return (finalFee, appliedDiscount);
    }

    /**
     * @notice Updates user volume and recalculates fee tier
     * @param user Address of the user
     * @param tradeVolume Volume of the trade
     */
    function updateUserVolume(
        address user,
        uint256 tradeVolume
    ) external onlyRole(accessControl.OPERATOR_ROLE()) nonReentrant {
        UserVolumeData storage userData = userVolumeData[user];

        // Update volume data
        userData.totalVolume += tradeVolume;
        userData.tradeCount += 1;
        userData.lastTradeTimestamp = block.timestamp;

        // Update 30-day volume (simplified - in production would need more sophisticated tracking)
        userData.last30DaysVolume += tradeVolume;

        // Update global volume
        totalMarketplaceVolume += tradeVolume;

        // Recalculate user's fee tier
        _updateUserFeeTier(user);

        emit UserVolumeUpdated(
            user,
            userData.totalVolume,
            userData.last30DaysVolume,
            userData.tradeCount
        );
    }

    // ============================================================================
    // INTERNAL CALCULATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Calculates base fees before discounts
     */
    function _calculateBaseFees(
        address collection,
        uint256 salePrice,
        bool isMaker
    ) internal view returns (uint256) {
        FeeConfig memory config = baseFeeConfig;

        if (!config.isActive) {
            return 0;
        }

        uint256 baseFee = isMaker ? config.makerFee : config.takerFee;
        return (salePrice * baseFee) / 10000;
    }

    /**
     * @notice Calculates user-specific discount
     */
    function _calculateUserDiscount(
        address user
    ) internal view returns (uint256) {
        uint256 totalDiscount = 0;

        // Add fee tier discount
        FeeTier memory userTier = userFeeTiers[user];
        totalDiscount += userTier.discountBps;

        // Add VIP discount
        VIPStatus memory userVIP = vipStatus[user];
        if (userVIP.isVIP && block.timestamp < userVIP.vipExpiryTimestamp) {
            totalDiscount += userVIP.vipDiscountBps;
        }

        return totalDiscount;
    }

    /**
     * @notice Applies collection-specific fee overrides
     */
    function _applyCollectionOverride(
        address collection,
        uint256 baseFee,
        bool isMaker
    ) internal view returns (uint256 finalFee, uint256 collectionDiscount) {
        CollectionFeeOverride memory feeOverride = collectionFeeOverrides[
            collection
        ];

        if (!feeOverride.hasOverride) {
            return (baseFee, 0);
        }

        // Apply collection-specific fee override rates
        uint256 overrideRate = isMaker
            ? feeOverride.makerFeeOverride
            : feeOverride.takerFeeOverride;
        if (overrideRate > 0) {
            // Calculate fee using override rate instead of base fee
            // Need to extract sale price from baseFee calculation
            // baseFee = (salePrice * baseRate) / 10000
            // So salePrice = (baseFee * 10000) / baseRate
            uint256 baseRate = isMaker
                ? baseFeeConfig.makerFee
                : baseFeeConfig.takerFee;
            uint256 salePrice = (baseFee * 10000) / baseRate;
            finalFee = (salePrice * overrideRate) / 10000;
        } else {
            finalFee = baseFee;
        }

        // Apply collection discount
        collectionDiscount = feeOverride.discountBps;

        // Additional discount for verified collections
        if (feeOverride.isVerified) {
            collectionDiscount += 50; // 0.5% additional discount for verified collections
        }

        return (finalFee, collectionDiscount);
    }

    /**
     * @notice Validates fee parameters
     */
    function _validateFeeParams(
        uint256 makerFee,
        uint256 takerFee,
        uint256 listingFee
    ) internal pure {
        if (makerFee > 1000 || takerFee > 1000) {
            // Max 10%
            revert Fee__InvalidRoyaltyFee();
        }
        // listingFee is in wei, so no percentage validation needed
    }

    /**
     * @notice Updates user's fee tier based on volume
     */
    function _updateUserFeeTier(address user) internal {
        UserVolumeData memory userData = userVolumeData[user];
        uint256 currentTierId = userFeeTiers[user].tierId;
        uint256 newTierId = 0;
        uint256 newDiscountBps = 0;

        // Find appropriate tier based on volume
        for (uint256 i = feeTierConfigs.length; i > 0; i--) {
            FeeTierConfig memory tierConfig = feeTierConfigs[i - 1];
            if (
                tierConfig.isActive &&
                userData.totalVolume >= tierConfig.volumeThreshold
            ) {
                newTierId = i - 1;
                newDiscountBps = tierConfig.discountBps;
                break;
            }
        }

        // Update tier if changed
        if (newTierId != currentTierId) {
            userFeeTiers[user] = FeeTier({
                tierId: newTierId,
                discountBps: newDiscountBps,
                lastUpdated: block.timestamp
            });

            emit FeeTierUpdated(user, currentTierId, newTierId, newDiscountBps);
        }
    }

    /**
     * @notice Initializes default fee configuration
     */
    function _initializeDefaultFees() internal {
        baseFeeConfig = FeeConfig({
            makerFee: 250, // 2.5% maker fee
            takerFee: 250, // 2.5% taker fee
            listingFee: 0, // No listing fee initially
            auctionFee: 50, // Additional 0.5% for auctions
            bundleFee: 100, // Additional 1% for bundles
            isActive: true
        });
    }

    /**
     * @notice Initializes default fee tiers
     */
    function _initializeDefaultTiers() internal {
        // Tier 0: Bronze (0-10 ETH volume) - 0% discount
        feeTierConfigs.push(
            FeeTierConfig({
                volumeThreshold: 0,
                discountBps: 0,
                tierName: "Bronze",
                isActive: true
            })
        );

        // Tier 1: Silver (10-50 ETH volume) - 0.5% discount
        feeTierConfigs.push(
            FeeTierConfig({
                volumeThreshold: 10 ether,
                discountBps: 50,
                tierName: "Silver",
                isActive: true
            })
        );

        // Tier 2: Gold (50-200 ETH volume) - 1% discount
        feeTierConfigs.push(
            FeeTierConfig({
                volumeThreshold: 50 ether,
                discountBps: 100,
                tierName: "Gold",
                isActive: true
            })
        );

        // Tier 3: Platinum (200+ ETH volume) - 2% discount
        feeTierConfigs.push(
            FeeTierConfig({
                volumeThreshold: 200 ether,
                discountBps: 200,
                tierName: "Platinum",
                isActive: true
            })
        );
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Updates base fee configuration
     * @param newConfig New fee configuration
     */
    function updateBaseFeeConfig(
        FeeConfig calldata newConfig
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        _validateFeeParams(
            newConfig.makerFee,
            newConfig.takerFee,
            newConfig.listingFee
        );

        FeeConfig memory oldConfig = baseFeeConfig;
        baseFeeConfig = newConfig;

        emit FeeConfigUpdated(
            oldConfig.makerFee,
            newConfig.makerFee,
            oldConfig.takerFee,
            newConfig.takerFee,
            msg.sender
        );
    }

    /**
     * @notice Sets collection-specific fee override
     * @param collection Address of the collection
     * @param feeOverride Fee override configuration
     */
    function setCollectionFeeOverride(
        address collection,
        CollectionFeeOverride calldata feeOverride
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        if (collection == address(0)) {
            revert Fee__InvalidOwner();
        }

        collectionFeeOverrides[collection] = CollectionFeeOverride({
            makerFeeOverride: feeOverride.makerFeeOverride,
            takerFeeOverride: feeOverride.takerFeeOverride,
            discountBps: feeOverride.discountBps,
            hasOverride: feeOverride.hasOverride,
            isVerified: feeOverride.isVerified,
            setAt: block.timestamp
        });

        emit CollectionFeeOverrideSet(
            collection,
            feeOverride.makerFeeOverride,
            feeOverride.takerFeeOverride,
            feeOverride.discountBps,
            feeOverride.isVerified
        );
    }

    /**
     * @notice Updates user's VIP status
     * @param user Address of the user
     * @param vipData VIP status configuration
     */
    function updateVIPStatus(
        address user,
        VIPStatus calldata vipData
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        if (user == address(0)) {
            revert Fee__InvalidOwner();
        }

        vipStatus[user] = vipData;

        emit VIPStatusUpdated(
            user,
            vipData.isVIP,
            vipData.vipDiscountBps,
            vipData.vipExpiryTimestamp,
            vipData.vipTier
        );
    }

    /**
     * @notice Adds or updates a fee tier configuration
     * @param tierId ID of the tier to update
     * @param tierConfig New tier configuration
     */
    function updateFeeTier(
        uint256 tierId,
        FeeTierConfig calldata tierConfig
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        if (tierId >= feeTierConfigs.length) {
            feeTierConfigs.push(tierConfig);
        } else {
            feeTierConfigs[tierId] = tierConfig;
        }
    }

    /**
     * @notice Updates fee recipient address
     * @param newFeeRecipient New fee recipient address
     */
    function updateFeeRecipient(
        address newFeeRecipient
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        if (newFeeRecipient == address(0)) {
            revert Fee__InvalidOwner();
        }

        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;

        emit FeeUpdated(
            "feeRecipient",
            uint256(uint160(oldRecipient)),
            uint256(uint160(newFeeRecipient)),
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Emergency pause contract
     */
    function emergencyPause()
        external
        onlyRole(accessControl.EMERGENCY_ROLE())
    {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(accessControl.ADMIN_ROLE()) {
        _unpause();
    }

    /**
     * @notice Batch update user volumes (for migration or corrections)
     * @param users Array of user addresses
     * @param volumes Array of volume amounts
     */
    function batchUpdateUserVolumes(
        address[] calldata users,
        uint256[] calldata volumes
    ) external onlyRole(accessControl.ADMIN_ROLE()) nonReentrant {
        if (users.length != volumes.length || users.length == 0) {
            revert Fee__InvalidRoyaltyFee();
        }

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                userVolumeData[users[i]].totalVolume = volumes[i];
                _updateUserFeeTier(users[i]);
            }
        }
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets current base fee configuration
     * @return config Current fee configuration
     */
    function getBaseFeeConfig()
        external
        view
        returns (FeeConfig memory config)
    {
        return baseFeeConfig;
    }

    /**
     * @notice Gets user's current fee tier information
     * @param user Address of the user
     * @return tier User's fee tier data
     */
    function getUserFeeTier(
        address user
    ) external view returns (FeeTier memory tier) {
        return userFeeTiers[user];
    }

    /**
     * @notice Gets collection fee override information
     * @param collection Address of the collection
     * @return feeOverride Collection's fee override data
     */
    function getCollectionFeeOverride(
        address collection
    ) external view returns (CollectionFeeOverride memory feeOverride) {
        return collectionFeeOverrides[collection];
    }

    /**
     * @notice Gets user's volume data
     * @param user Address of the user
     * @return volumeData User's volume tracking data
     */
    function getUserVolumeData(
        address user
    ) external view returns (UserVolumeData memory volumeData) {
        return userVolumeData[user];
    }

    /**
     * @notice Gets user's VIP status
     * @param user Address of the user
     * @return vipData User's VIP status data
     */
    function getUserVIPStatus(
        address user
    ) external view returns (VIPStatus memory vipData) {
        return vipStatus[user];
    }

    /**
     * @notice Gets fee tier configuration by ID
     * @param tierId ID of the fee tier
     * @return tierConfig Fee tier configuration
     */
    function getFeeTierConfig(
        uint256 tierId
    ) external view returns (FeeTierConfig memory tierConfig) {
        if (tierId >= feeTierConfigs.length) {
            revert Fee__InvalidRoyaltyFee();
        }
        return feeTierConfigs[tierId];
    }

    /**
     * @notice Gets all fee tier configurations
     * @return tierConfigs Array of all fee tier configurations
     */
    function getAllFeeTierConfigs()
        external
        view
        returns (FeeTierConfig[] memory tierConfigs)
    {
        return feeTierConfigs;
    }

    /**
     * @notice Gets total number of fee tiers
     * @return count Number of fee tiers
     */
    function getFeeTierCount() external view returns (uint256 count) {
        return feeTierConfigs.length;
    }

    /**
     * @notice Calculates effective fee rate for a user and collection
     * @param user Address of the user
     * @param collection Address of the collection
     * @param isMaker Whether calculating for maker (true) or taker (false)
     * @return effectiveRate Effective fee rate in basis points
     */
    function getEffectiveFeeRate(
        address user,
        address collection,
        bool isMaker
    ) external view returns (uint256 effectiveRate) {
        // Get base fee rate
        uint256 baseFeeRate = isMaker
            ? baseFeeConfig.makerFee
            : baseFeeConfig.takerFee;

        // Apply collection override if exists
        CollectionFeeOverride memory feeOverride = collectionFeeOverrides[
            collection
        ];
        if (feeOverride.hasOverride) {
            uint256 overrideRate = isMaker
                ? feeOverride.makerFeeOverride
                : feeOverride.takerFeeOverride;
            if (overrideRate > 0) {
                baseFeeRate = overrideRate;
            }
        }

        // Calculate total discount
        uint256 totalDiscount = _calculateUserDiscount(user);
        if (feeOverride.hasOverride) {
            totalDiscount += feeOverride.discountBps;
            if (feeOverride.isVerified) {
                totalDiscount += 50; // Additional verified collection discount
            }
        }

        // Cap discount at 50%
        if (totalDiscount > 5000) {
            totalDiscount = 5000;
        }

        // Apply discount
        effectiveRate = baseFeeRate - ((baseFeeRate * totalDiscount) / 10000);
        return effectiveRate;
    }

    /**
     * @notice Checks if user qualifies for next fee tier
     * @param user Address of the user
     * @return canUpgrade Whether user can upgrade to next tier
     * @return nextTierId ID of the next tier
     * @return volumeNeeded Additional volume needed for upgrade
     */
    function checkTierUpgradeEligibility(
        address user
    )
        external
        view
        returns (bool canUpgrade, uint256 nextTierId, uint256 volumeNeeded)
    {
        FeeTier memory currentTier = userFeeTiers[user];
        UserVolumeData memory userData = userVolumeData[user];

        // Check if there's a next tier
        if (currentTier.tierId + 1 >= feeTierConfigs.length) {
            return (false, 0, 0);
        }

        FeeTierConfig memory nextTier = feeTierConfigs[currentTier.tierId + 1];

        if (!nextTier.isActive) {
            return (false, 0, 0);
        }

        if (userData.totalVolume >= nextTier.volumeThreshold) {
            return (true, currentTier.tierId + 1, 0);
        } else {
            return (
                false,
                currentTier.tierId + 1,
                nextTier.volumeThreshold - userData.totalVolume
            );
        }
    }
}
