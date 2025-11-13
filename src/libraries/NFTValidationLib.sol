// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title NFTValidationLib
 * @notice Library for NFT ownership and approval validation
 * @dev Centralizes NFT validation logic to reduce code duplication
 */
library NFTValidationLib {
    // ============================================================================
    // ERRORS
    // ============================================================================

    error NFTValidation__NotOwner();
    error NFTValidation__NotApproved();
    error NFTValidation__InsufficientBalance();
    error NFTValidation__UnsupportedStandard();
    error NFTValidation__ZeroAddress();
    error NFTValidation__InvalidAmount();

    // ============================================================================
    // ENUMS
    // ============================================================================

    enum NFTStandard {
        ERC721,
        ERC1155,
        UNKNOWN
    }

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct ValidationParams {
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        address owner;
        address spender;
    }

    struct ValidationResult {
        bool isValid;
        NFTStandard standard;
        string errorMessage;
    }

    // ============================================================================
    // MAIN VALIDATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates NFT ownership and approval for ERC721
     * @param params Validation parameters
     * @return result Validation result
     */
    function validateERC721(ValidationParams memory params) internal view returns (ValidationResult memory result) {
        result.standard = NFTStandard.ERC721;

        try IERC721(params.nftContract).ownerOf(params.tokenId) returns (address owner) {
            if (owner != params.owner) {
                result.errorMessage = "Not the owner";
                return result;
            }
        } catch {
            result.errorMessage = "Failed to get owner";
            return result;
        }

        // Check approval
        if (!_isERC721Approved(params)) {
            result.errorMessage = "Not approved";
            return result;
        }

        result.isValid = true;
        return result;
    }

    /**
     * @notice Validates NFT ownership and approval for ERC1155
     * @param params Validation parameters
     * @return result Validation result
     */
    function validateERC1155(ValidationParams memory params) internal view returns (ValidationResult memory result) {
        result.standard = NFTStandard.ERC1155;

        if (params.amount == 0) {
            result.errorMessage = "Amount must be greater than zero";
            return result;
        }

        try IERC1155(params.nftContract).balanceOf(params.owner, params.tokenId) returns (uint256 balance) {
            if (balance < params.amount) {
                result.errorMessage = "Insufficient balance";
                return result;
            }
        } catch {
            result.errorMessage = "Failed to get balance";
            return result;
        }

        // Check approval
        if (!_isERC1155Approved(params)) {
            result.errorMessage = "Not approved";
            return result;
        }

        result.isValid = true;
        return result;
    }

    /**
     * @notice Auto-detects NFT standard and validates accordingly
     * @param params Validation parameters
     * @return result Validation result
     */
    function validateNFT(ValidationParams memory params) internal view returns (ValidationResult memory result) {
        // Basic parameter validation
        if (params.nftContract == address(0) || params.owner == address(0)) {
            result.errorMessage = "Zero address provided";
            return result;
        }

        NFTStandard standard = detectNFTStandard(params.nftContract);

        if (standard == NFTStandard.ERC721) {
            return validateERC721(params);
        } else if (standard == NFTStandard.ERC1155) {
            return validateERC1155(params);
        } else {
            result.errorMessage = "Unsupported NFT standard";
            return result;
        }
    }

    /**
     * @notice Detects the NFT standard of a contract
     * @param nftContract Address of the NFT contract
     * @return standard The detected NFT standard
     */
    function detectNFTStandard(address nftContract) internal view returns (NFTStandard standard) {
        // Return UNKNOWN for zero address
        if (nftContract == address(0)) {
            return NFTStandard.UNKNOWN;
        }

        try IERC165(nftContract).supportsInterface(0x80ac58cd) returns (bool isERC721) {
            if (isERC721) {
                return NFTStandard.ERC721;
            }
        } catch {}

        try IERC165(nftContract).supportsInterface(0xd9b67a26) returns (bool isERC1155) {
            if (isERC1155) {
                return NFTStandard.ERC1155;
            }
        } catch {}

        return NFTStandard.UNKNOWN;
    }

    // ============================================================================
    // BATCH VALIDATION FUNCTIONS
    // ============================================================================

    /**
     * @notice Validates multiple NFTs in a batch
     * @param paramsList Array of validation parameters
     * @return results Array of validation results
     */
    function batchValidateNFTs(ValidationParams[] memory paramsList)
        internal
        view
        returns (ValidationResult[] memory results)
    {
        results = new ValidationResult[](paramsList.length);

        for (uint256 i = 0; i < paramsList.length; i++) {
            results[i] = validateNFT(paramsList[i]);
        }

        return results;
    }

    /**
     * @notice Checks if all validations in a batch passed
     * @param results Array of validation results
     * @return allValid True if all validations passed
     */
    function areAllValidationsValid(ValidationResult[] memory results) internal pure returns (bool allValid) {
        for (uint256 i = 0; i < results.length; i++) {
            if (!results[i].isValid) {
                return false;
            }
        }
        return true;
    }

    // ============================================================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Checks if ERC721 token is approved for spender
     * @param params Validation parameters
     * @return isApproved True if approved
     */
    function _isERC721Approved(ValidationParams memory params) private view returns (bool isApproved) {
        // First check if approved for all
        try IERC721(params.nftContract).isApprovedForAll(params.owner, params.spender) returns (bool approvedForAll) {
            if (approvedForAll) {
                return true;
            }
        } catch {}

        // Then check if specifically approved
        try IERC721(params.nftContract).getApproved(params.tokenId) returns (address approved) {
            return approved == params.spender;
        } catch {}

        return false;
    }

    /**
     * @notice Checks if ERC1155 tokens are approved for spender
     * @param params Validation parameters
     * @return isApproved True if approved
     */
    function _isERC1155Approved(ValidationParams memory params) private view returns (bool isApproved) {
        try IERC1155(params.nftContract).isApprovedForAll(params.owner, params.spender) returns (bool approvedForAll) {
            return approvedForAll;
        } catch {}

        return false;
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates validation parameters for NFT validation
     * @param nftContract Address of the NFT contract
     * @param tokenId ID of the token to validate
     * @param amount Amount of tokens to validate (1 for ERC721)
     * @param owner Address of the owner to validate
     * @param spender Address of the spender to validate
     * @return params Validation parameters
     */
    function createValidationParams(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        address owner,
        address spender
    ) internal pure returns (ValidationParams memory params) {
        params = ValidationParams({
            nftContract: nftContract, tokenId: tokenId, amount: amount, owner: owner, spender: spender
        });
    }
}
