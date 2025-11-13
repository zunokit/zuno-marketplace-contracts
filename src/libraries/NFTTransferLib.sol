// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {NFTValidationLib} from "./NFTValidationLib.sol";

/**
 * @title NFTTransferLib
 * @notice Library for handling NFT transfers across different standards
 * @dev Centralizes NFT transfer logic for both ERC721 and ERC1155
 */
library NFTTransferLib {
    // ============================================================================
    // ERRORS
    // ============================================================================

    error NFTTransfer__TransferFailed();
    error NFTTransfer__UnsupportedStandard();
    error NFTTransfer__ZeroAddress();
    error NFTTransfer__InvalidAmount();

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Transfer parameters
     */
    struct TransferParams {
        address nftContract;
        uint256 tokenId;
        uint256 amount; // 1 for ERC721, actual amount for ERC1155
        address from;
        address to;
        NFTValidationLib.NFTStandard standard;
    }

    /**
     * @notice Batch transfer parameters
     */
    struct BatchTransferParams {
        address nftContract;
        uint256[] tokenIds;
        uint256[] amounts;
        address from;
        address to;
        NFTValidationLib.NFTStandard standard;
    }

    /**
     * @notice Transfer result
     */
    struct TransferResult {
        bool success;
        string errorMessage;
        uint256 transferredCount; // For batch operations
    }

    // ============================================================================
    // SINGLE TRANSFER FUNCTIONS
    // ============================================================================

    /**
     * @notice Transfers a single NFT (auto-detects standard)
     * @param params Transfer parameters
     * @return result Transfer result
     */
    function transferNFT(TransferParams memory params) internal returns (TransferResult memory result) {
        // Validate parameters
        if (params.nftContract == address(0) || params.from == address(0) || params.to == address(0)) {
            result.errorMessage = "Zero address provided";
            return result;
        }

        if (params.amount == 0) {
            result.errorMessage = "Invalid amount";
            return result;
        }

        // Auto-detect standard if not provided
        if (params.standard == NFTValidationLib.NFTStandard.UNKNOWN) {
            params.standard = NFTValidationLib.detectNFTStandard(params.nftContract);
        }

        // Execute transfer based on standard
        if (params.standard == NFTValidationLib.NFTStandard.ERC721) {
            return _transferERC721(params);
        } else if (params.standard == NFTValidationLib.NFTStandard.ERC1155) {
            return _transferERC1155(params);
        } else {
            result.errorMessage = "Unsupported NFT standard";
            return result;
        }
    }

    /**
     * @notice Transfers ERC721 NFT
     * @param params Transfer parameters
     * @return result Transfer result
     */
    function transferERC721(TransferParams memory params) internal returns (TransferResult memory result) {
        params.standard = NFTValidationLib.NFTStandard.ERC721;
        return _transferERC721(params);
    }

    /**
     * @notice Transfers ERC1155 NFT
     * @param params Transfer parameters
     * @return result Transfer result
     */
    function transferERC1155(TransferParams memory params) internal returns (TransferResult memory result) {
        params.standard = NFTValidationLib.NFTStandard.ERC1155;
        return _transferERC1155(params);
    }

    // ============================================================================
    // BATCH TRANSFER FUNCTIONS
    // ============================================================================

    /**
     * @notice Transfers multiple NFTs in batch
     * @param params Batch transfer parameters
     * @return result Transfer result with count
     */
    function batchTransferNFTs(BatchTransferParams memory params) internal returns (TransferResult memory result) {
        // Validate parameters
        if (params.tokenIds.length != params.amounts.length) {
            result.errorMessage = "Array length mismatch";
            return result;
        }

        if (params.tokenIds.length == 0) {
            result.errorMessage = "Empty arrays";
            return result;
        }

        // Auto-detect standard if not provided
        if (params.standard == NFTValidationLib.NFTStandard.UNKNOWN) {
            params.standard = NFTValidationLib.detectNFTStandard(params.nftContract);
        }

        // Execute batch transfer based on standard
        if (params.standard == NFTValidationLib.NFTStandard.ERC721) {
            return _batchTransferERC721(params);
        } else if (params.standard == NFTValidationLib.NFTStandard.ERC1155) {
            return _batchTransferERC1155(params);
        } else {
            result.errorMessage = "Unsupported NFT standard";
            return result;
        }
    }

    // ============================================================================
    // INTERNAL TRANSFER FUNCTIONS
    // ============================================================================

    /**
     * @notice Internal ERC721 transfer
     * @param params Transfer parameters
     * @return result Transfer result
     */
    function _transferERC721(TransferParams memory params) private returns (TransferResult memory result) {
        try IERC721(params.nftContract).transferFrom(params.from, params.to, params.tokenId) {
            result.success = true;
            result.transferredCount = 1;
        } catch Error(string memory reason) {
            result.errorMessage = reason;
        } catch {
            result.errorMessage = "ERC721 transfer failed";
        }
        return result;
    }

    /**
     * @notice Internal ERC1155 transfer
     * @param params Transfer parameters
     * @return result Transfer result
     */
    function _transferERC1155(TransferParams memory params) private returns (TransferResult memory result) {
        try IERC1155(params.nftContract).safeTransferFrom(params.from, params.to, params.tokenId, params.amount, "") {
            result.success = true;
            result.transferredCount = 1;
        } catch Error(string memory reason) {
            result.errorMessage = reason;
        } catch {
            result.errorMessage = "ERC1155 transfer failed";
        }
        return result;
    }

    /**
     * @notice Internal batch ERC721 transfer
     * @param params Batch transfer parameters
     * @return result Transfer result
     */
    function _batchTransferERC721(BatchTransferParams memory params) private returns (TransferResult memory result) {
        uint256 successCount = 0;

        for (uint256 i = 0; i < params.tokenIds.length; i++) {
            try IERC721(params.nftContract).transferFrom(params.from, params.to, params.tokenIds[i]) {
                successCount++;
            } catch {
                if (bytes(result.errorMessage).length == 0) {
                    result.errorMessage = string(abi.encodePacked("Transfer failed at index ", _toString(i)));
                }
            }
        }

        result.transferredCount = successCount;
        result.success = (successCount == params.tokenIds.length);
        return result;
    }

    /**
     * @notice Internal batch ERC1155 transfer
     * @param params Batch transfer parameters
     * @return result Transfer result
     */
    function _batchTransferERC1155(BatchTransferParams memory params) private returns (TransferResult memory result) {
        try IERC1155(params.nftContract)
            .safeBatchTransferFrom(params.from, params.to, params.tokenIds, params.amounts, "") {
            result.success = true;
            result.transferredCount = params.tokenIds.length;
        } catch Error(string memory reason) {
            result.errorMessage = reason;
        } catch {
            result.errorMessage = "ERC1155 batch transfer failed";
        }
        return result;
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Creates transfer parameters struct
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param amount Amount (1 for ERC721)
     * @param from From address
     * @param to To address
     * @return params Transfer parameters struct
     */
    function createTransferParams(address nftContract, uint256 tokenId, uint256 amount, address from, address to)
        internal
        pure
        returns (TransferParams memory params)
    {
        return TransferParams({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            from: from,
            to: to,
            standard: NFTValidationLib.NFTStandard.UNKNOWN
        });
    }

    /**
     * @notice Creates batch transfer parameters struct
     * @param nftContract NFT contract address
     * @param tokenIds Array of token IDs
     * @param amounts Array of amounts
     * @param from From address
     * @param to To address
     * @return params Batch transfer parameters struct
     */
    function createBatchTransferParams(
        address nftContract,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        address from,
        address to
    ) internal pure returns (BatchTransferParams memory params) {
        return BatchTransferParams({
            nftContract: nftContract,
            tokenIds: tokenIds,
            amounts: amounts,
            from: from,
            to: to,
            standard: NFTValidationLib.NFTStandard.UNKNOWN
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
     * @notice Validates transfer parameters
     * @param params Transfer parameters
     * @return isValid True if parameters are valid
     * @return errorMessage Error message if invalid
     */
    function validateTransferParams(TransferParams memory params)
        internal
        pure
        returns (bool isValid, string memory errorMessage)
    {
        if (params.nftContract == address(0)) {
            return (false, "Invalid NFT contract");
        }
        if (params.from == address(0)) {
            return (false, "Invalid from address");
        }
        if (params.to == address(0)) {
            return (false, "Invalid to address");
        }
        if (params.amount == 0) {
            return (false, "Invalid amount");
        }
        return (true, "");
    }
}
