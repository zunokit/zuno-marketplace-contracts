// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import {Fee} from "src/common/Fee.sol";

/**
 * @title RoyaltyLib
 * @notice Library for calculating royalties from various NFT contracts
 * @dev Centralizes complex royalty calculation logic from BaseNFTExchange
 */
library RoyaltyLib {
    // ============================================================================
    // ERRORS
    // ============================================================================

    error Royalty__InvalidContract();
    error Royalty__InvalidAmount();

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct RoyaltyInfo {
        address receiver;
        uint256 amount;
        uint256 rate; // in basis points
        bool hasRoyalty;
        string source; // "ERC2981", "BaseCollection", "Fee", "None"
    }

    struct RoyaltyParams {
        address nftContract;
        uint256 tokenId;
        uint256 salePrice;
        uint256 maxRoyaltyRate; // maximum allowed royalty rate in basis points
    }

    // ============================================================================
    // MAIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets royalty information using multiple fallback methods
     * @param params Royalty calculation parameters
     * @return info Comprehensive royalty information
     */
    function getRoyaltyInfo(RoyaltyParams memory params) internal view returns (RoyaltyInfo memory info) {
        // Return no royalty for zero address
        if (params.nftContract == address(0)) {
            return RoyaltyInfo({receiver: address(0), amount: 0, rate: 0, hasRoyalty: false, source: "None"});
        }

        // Method 1: Try ERC2981 standard (takes precedence)
        info = _tryERC2981Royalty(params);
        if (info.hasRoyalty) {
            return info;
        }

        // Method 2: Try Fee contract approach (for MockERC721/MockERC1155 and BaseCollection)
        info = _tryFeeContractRoyalty(params);
        if (info.hasRoyalty) {
            return info;
        }

        // Method 3: Try BaseCollection approach
        info = _tryBaseCollectionRoyalty(params);
        if (info.hasRoyalty) {
            return info;
        }

        // No royalty found
        return RoyaltyInfo({receiver: address(0), amount: 0, rate: 0, hasRoyalty: false, source: "None"});
    }

    /**
     * @notice Simplified royalty calculation for backward compatibility
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param salePrice Sale price
     * @return receiver Royalty receiver address
     * @return royaltyAmount Royalty amount
     */
    function calculateRoyalty(address nftContract, uint256 tokenId, uint256 salePrice)
        internal
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyParams memory params = RoyaltyParams({
            nftContract: nftContract,
            tokenId: tokenId,
            salePrice: salePrice,
            maxRoyaltyRate: 1000 // 10% max royalty
        });

        RoyaltyInfo memory info = getRoyaltyInfo(params);
        return (info.receiver, info.amount);
    }

    // ============================================================================
    // INTERNAL ROYALTY METHODS
    // ============================================================================

    /**
     * @notice Attempts to get royalty from Fee contract
     * @param params Royalty parameters
     * @return info Royalty information
     */
    function _tryFeeContractRoyalty(RoyaltyParams memory params) private view returns (RoyaltyInfo memory info) {
        address feeContractAddress = _callGetFeeContract(params.nftContract);
        if (feeContractAddress != address(0)) {
            return _getFeeContractRoyalty(feeContractAddress, params);
        }

        return _createEmptyRoyaltyInfo();
    }

    /**
     * @notice Gets royalty from Fee contract
     * @param feeContractAddress Fee contract address
     * @param params Royalty parameters
     * @return info Royalty information
     */
    function _getFeeContractRoyalty(address feeContractAddress, RoyaltyParams memory params)
        private
        view
        returns (RoyaltyInfo memory info)
    {
        (bool hasFeeContract, uint256 royaltyFee) = _getFeeContractRoyaltyRateWithSuccess(feeContractAddress);
        if (!hasFeeContract) {
            return _createEmptyRoyaltyInfo();
        }

        // If Fee contract has 0% royalty, return empty to allow fallback to other methods
        if (royaltyFee == 0) {
            return _createEmptyRoyaltyInfo();
        }

        if (royaltyFee > params.maxRoyaltyRate) {
            return _createEmptyRoyaltyInfo();
        }

        address feeOwner = _getFeeContractOwner(feeContractAddress);
        if (feeOwner == address(0)) {
            return _createEmptyRoyaltyInfo();
        }

        uint256 royaltyAmount = (params.salePrice * royaltyFee) / 10000;
        return
            RoyaltyInfo({receiver: feeOwner, amount: royaltyAmount, rate: royaltyFee, hasRoyalty: true, source: "Fee"});
    }

    /**
     * @notice Gets royalty rate from Fee contract
     * @param feeContractAddress Fee contract address
     * @return royaltyFee Royalty fee in basis points
     */
    function _getFeeContractRoyaltyRate(address feeContractAddress) private view returns (uint256 royaltyFee) {
        try Fee(feeContractAddress).getRoyaltyFee() returns (uint256 fee) {
            return fee;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Gets royalty rate from Fee contract with success indicator
     * @param feeContractAddress Fee contract address
     * @return hasFeeContract Whether the contract is a valid Fee contract
     * @return royaltyFee Royalty fee in basis points
     */
    function _getFeeContractRoyaltyRateWithSuccess(address feeContractAddress)
        private
        view
        returns (bool hasFeeContract, uint256 royaltyFee)
    {
        try Fee(feeContractAddress).getRoyaltyFee() returns (uint256 fee) {
            return (true, fee);
        } catch {
            return (false, 0);
        }
    }

    /**
     * @notice Gets owner from Fee contract
     * @param feeContractAddress Fee contract address
     * @return owner Owner address
     */
    function _getFeeContractOwner(address feeContractAddress) private view returns (address owner) {
        try Fee(feeContractAddress).owner() returns (address ownerAddr) {
            return ownerAddr;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Attempts to get royalty from BaseCollection
     * @param params Royalty parameters
     * @return info Royalty information
     */
    function _tryBaseCollectionRoyalty(RoyaltyParams memory params) private view returns (RoyaltyInfo memory info) {
        (bool hasBaseCollection, uint256 royaltyFee) = _getBaseCollectionRoyaltyRateWithSuccess(params.nftContract);
        if (!hasBaseCollection) {
            return _createEmptyRoyaltyInfo();
        }

        if (royaltyFee > params.maxRoyaltyRate) {
            return _createEmptyRoyaltyInfo();
        }

        address owner = _getBaseCollectionOwner(params.nftContract);
        if (owner == address(0)) {
            return _createEmptyRoyaltyInfo();
        }

        uint256 royaltyAmount = (params.salePrice * royaltyFee) / 10000;
        return RoyaltyInfo({
            receiver: owner, amount: royaltyAmount, rate: royaltyFee, hasRoyalty: true, source: "BaseCollection"
        });
    }

    /**
     * @notice Gets royalty rate from BaseCollection
     * @param nftContract BaseCollection contract address
     * @return royaltyFee Royalty fee in basis points
     */
    function _getBaseCollectionRoyaltyRate(address nftContract) private view returns (uint256 royaltyFee) {
        try BaseCollection(nftContract).getRoyaltyFee() returns (uint256 fee) {
            return fee;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Gets royalty rate from BaseCollection with success indicator
     * @param nftContract BaseCollection contract address
     * @return hasBaseCollection Whether the contract implements BaseCollection
     * @return royaltyFee Royalty fee in basis points
     */
    function _getBaseCollectionRoyaltyRateWithSuccess(address nftContract)
        private
        view
        returns (bool hasBaseCollection, uint256 royaltyFee)
    {
        try BaseCollection(nftContract).getRoyaltyFee() returns (uint256 fee) {
            return (true, fee);
        } catch {
            return (false, 0);
        }
    }

    /**
     * @notice Gets owner from BaseCollection
     * @param nftContract BaseCollection contract address
     * @return owner Owner address
     */
    function _getBaseCollectionOwner(address nftContract) private view returns (address owner) {
        try BaseCollection(nftContract).owner() returns (address ownerAddr) {
            return ownerAddr;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Attempts to get royalty from ERC2981 standard
     * @param params Royalty parameters
     * @return info Royalty information
     */
    function _tryERC2981Royalty(RoyaltyParams memory params) private view returns (RoyaltyInfo memory info) {
        (address receiver, uint256 royaltyAmount) =
            _getERC2981RoyaltyInfo(params.nftContract, params.tokenId, params.salePrice);

        if (receiver == address(0) || royaltyAmount == 0) {
            return _createEmptyRoyaltyInfo();
        }

        uint256 royaltyRate = (royaltyAmount * 10000) / params.salePrice;
        if (royaltyRate > params.maxRoyaltyRate) {
            return _createEmptyRoyaltyInfo();
        }

        return RoyaltyInfo({
            receiver: receiver, amount: royaltyAmount, rate: royaltyRate, hasRoyalty: true, source: "ERC2981"
        });
    }

    /**
     * @notice Gets royalty info from ERC2981 standard
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param salePrice Sale price
     * @return receiver Royalty receiver
     * @return royaltyAmount Royalty amount
     */
    function _getERC2981RoyaltyInfo(address nftContract, uint256 tokenId, uint256 salePrice)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address royaltyReceiver, uint256 amount) {
            return (royaltyReceiver, amount);
        } catch {
            return (address(0), 0);
        }
    }

    /**
     * @notice Creates empty royalty info struct
     * @return info Empty royalty information
     */
    function _createEmptyRoyaltyInfo() private pure returns (RoyaltyInfo memory info) {
        return RoyaltyInfo({receiver: address(0), amount: 0, rate: 0, hasRoyalty: false, source: "None"});
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Low-level call to getFeeContract() method
     * @param contractAddress Contract address to call
     * @return feeContract Fee contract address
     */
    function _callGetFeeContract(address contractAddress) internal view returns (address feeContract) {
        (bool success, bytes memory data) = contractAddress.staticcall(abi.encodeWithSignature("getFeeContract()"));

        if (success && data.length >= 32) {
            return abi.decode(data, (address));
        }

        return address(0);
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates royalty rate against maximum allowed
     * @param royaltyRate Royalty rate in basis points
     * @param maxRate Maximum allowed rate in basis points
     * @return isValid True if rate is valid
     */
    function validateRoyaltyRate(uint256 royaltyRate, uint256 maxRate) internal pure returns (bool isValid) {
        return royaltyRate <= maxRate;
    }

    /**
     * @notice Calculates royalty amount from rate and price
     * @param salePrice Sale price
     * @param royaltyRate Royalty rate in basis points
     * @return royaltyAmount Calculated royalty amount
     */
    function calculateRoyaltyAmount(uint256 salePrice, uint256 royaltyRate)
        internal
        pure
        returns (uint256 royaltyAmount)
    {
        return (salePrice * royaltyRate) / 10000;
    }

    /**
     * @notice Creates royalty parameters struct
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param salePrice Sale price
     * @param maxRoyaltyRate Maximum royalty rate
     * @return params Royalty parameters struct
     */
    function createRoyaltyParams(address nftContract, uint256 tokenId, uint256 salePrice, uint256 maxRoyaltyRate)
        internal
        pure
        returns (RoyaltyParams memory params)
    {
        return RoyaltyParams({
            nftContract: nftContract, tokenId: tokenId, salePrice: salePrice, maxRoyaltyRate: maxRoyaltyRate
        });
    }
}
