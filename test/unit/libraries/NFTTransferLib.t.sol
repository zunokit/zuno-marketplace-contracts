// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/libraries/NFTTransferLib.sol";
import "src/libraries/NFTValidationLib.sol";
import "test/mocks/MockERC721.sol";
import "test/mocks/MockERC1155.sol";

/**
 * @title NFTTransferLibTest
 * @notice Comprehensive tests for NFTTransferLib library functions
 */
contract NFTTransferLibTest is Test {
    using NFTTransferLib for *;

    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;

    address public seller = address(0x1);
    address public buyer = address(0x2);
    address public marketplace = address(0x3);
    uint256 public tokenId = 1;

    function setUp() public {
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test 1155", "T1155");

        // Mint tokens to seller
        mockERC721.mint(seller, tokenId);
        mockERC1155.mint(seller, tokenId, 100);

        // Set approvals
        vm.startPrank(seller);
        mockERC721.setApprovalForAll(marketplace, true);
        mockERC1155.setApprovalForAll(marketplace, true);
        vm.stopPrank();
    }

    // ============================================================================
    // SAFE TRANSFER TESTS
    // ============================================================================

    function testTransferNFT_ERC721_Success() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertTrue(result.success);
        assertEq(result.errorMessage, "");
        assertEq(mockERC721.ownerOf(tokenId), buyer);
    }

    function testTransferNFT_ERC1155_Success() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 10,
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertTrue(result.success);
        assertEq(result.errorMessage, "");
        assertEq(mockERC1155.balanceOf(buyer, tokenId), 10);
        assertEq(mockERC1155.balanceOf(seller, tokenId), 90);
    }

    function testTransferNFT_InvalidContract() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(0), // Zero address
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.UNKNOWN
        });

        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertFalse(result.success);
        assertEq(result.errorMessage, "Zero address provided");
    }

    function testTransferNFT_ERC721_InvalidAmount() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 2, // Invalid amount for ERC721
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertFalse(result.success);
        assertTrue(bytes(result.errorMessage).length > 0);
    }

    function testTransferNFT_ERC1155_ZeroAmount() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 0, // Zero amount
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertFalse(result.success);
        assertEq(result.errorMessage, "Invalid amount");
    }

    // ============================================================================
    // BATCH TRANSFER TESTS
    // ============================================================================

    function testBatchTransferNFTs_ERC1155_Success() public {
        // Mint additional tokens
        mockERC1155.mint(seller, 2, 50);
        mockERC1155.mint(seller, 3, 75);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;

        NFTTransferLib.BatchTransferParams memory params = NFTTransferLib.BatchTransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenIds: tokenIds,
            amounts: amounts,
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.batchTransferNFTs(params);

        assertTrue(result.success);
        assertEq(result.errorMessage, "");

        // Verify transfers
        assertEq(mockERC1155.balanceOf(buyer, 1), 10);
        assertEq(mockERC1155.balanceOf(buyer, 2), 20);
        assertEq(mockERC1155.balanceOf(buyer, 3), 30);
    }

    function testBatchTransferNFTs_ERC721_Success() public {
        // Mint additional token (approval for all is already set in setUp)
        mockERC721.mint(seller, 2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        NFTTransferLib.BatchTransferParams memory params = NFTTransferLib.BatchTransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: buyer,
            tokenIds: tokenIds,
            amounts: amounts,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.batchTransferNFTs(params);

        // Only token 1 should transfer successfully (token 2 lacks approval)
        assertFalse(result.success); // Not all transfers succeeded
        assertEq(result.transferredCount, 1); // Only 1 transfer succeeded
        assertEq(mockERC721.ownerOf(1), buyer); // Token 1 transferred
        assertEq(mockERC721.ownerOf(2), seller); // Token 2 stayed with seller
        assertTrue(bytes(result.errorMessage).length > 0); // Should have error message
    }

    function testBatchTransferNFTs_ArrayLengthMismatch() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](3); // Different length
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;

        NFTTransferLib.BatchTransferParams memory params = NFTTransferLib.BatchTransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenIds: tokenIds,
            amounts: amounts,
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        NFTTransferLib.TransferResult memory result = NFTTransferLib.batchTransferNFTs(params);

        assertFalse(result.success);
        assertEq(result.errorMessage, "Array length mismatch");
    }

    // ============================================================================
    // VALIDATION TESTS
    // ============================================================================

    function testValidateTransferParams_Success() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        (bool isValid, string memory errorMessage) = NFTTransferLib.validateTransferParams(params);

        assertTrue(isValid);
        assertEq(bytes(errorMessage).length, 0);
    }

    function testValidateTransferParams_InvalidContract() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(0),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        (bool isValid, string memory errorMessage) = NFTTransferLib.validateTransferParams(params);

        assertFalse(isValid);
        assertEq(errorMessage, "Invalid NFT contract");
    }

    function testValidateTransferParams_InvalidFrom() public view {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: address(0),
            to: buyer,
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        (bool isValid, string memory errorMessage) = NFTTransferLib.validateTransferParams(params);

        assertFalse(isValid);
        assertEq(errorMessage, "Invalid from address");
    }

    function testValidateTransferParams_InvalidTo() public view {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: address(0),
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        (bool isValid, string memory errorMessage) = NFTTransferLib.validateTransferParams(params);

        assertFalse(isValid);
        assertEq(errorMessage, "Invalid to address");
    }

    function testValidateTransferParams_ZeroAmount() public view {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 0,
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        (bool isValid, string memory errorMessage) = NFTTransferLib.validateTransferParams(params);

        assertFalse(isValid);
        assertEq(errorMessage, "Invalid amount");
    }

    // ============================================================================
    // HELPER FUNCTION TESTS
    // ============================================================================

    function testCreateTransferParams() public view {
        NFTTransferLib.TransferParams memory params =
            NFTTransferLib.createTransferParams(address(mockERC721), tokenId, 1, seller, buyer);

        assertEq(params.nftContract, address(mockERC721));
        assertEq(params.tokenId, tokenId);
        assertEq(params.amount, 1);
        assertEq(params.from, seller);
        assertEq(params.to, buyer);
        assertTrue(params.standard == NFTValidationLib.NFTStandard.UNKNOWN);
    }

    function testCreateBatchTransferParams() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10;
        amounts[1] = 20;

        NFTTransferLib.BatchTransferParams memory params =
            NFTTransferLib.createBatchTransferParams(address(mockERC1155), tokenIds, amounts, seller, buyer);

        assertEq(params.nftContract, address(mockERC1155));
        assertEq(params.from, seller);
        assertEq(params.to, buyer);
        assertEq(params.tokenIds.length, 2);
        assertEq(params.amounts.length, 2);
        assertEq(params.tokenIds[0], 1);
        assertEq(params.tokenIds[1], 2);
        assertEq(params.amounts[0], 10);
        assertEq(params.amounts[1], 20);
        assertTrue(params.standard == NFTValidationLib.NFTStandard.UNKNOWN);
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    function testTransferToSameAddress() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC721),
            from: seller,
            to: seller, // Same address
            tokenId: tokenId,
            amount: 1,
            standard: NFTValidationLib.NFTStandard.ERC721
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertTrue(result.success);
        assertEq(mockERC721.ownerOf(tokenId), seller);
    }

    function testTransferERC1155_Success() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 10,
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertTrue(result.success);
        assertEq(mockERC1155.balanceOf(buyer, tokenId), 10);
    }

    function testTransferInsufficientBalance() public {
        NFTTransferLib.TransferParams memory params = NFTTransferLib.TransferParams({
            nftContract: address(mockERC1155),
            from: seller,
            to: buyer,
            tokenId: tokenId,
            amount: 200, // More than available (100)
            standard: NFTValidationLib.NFTStandard.ERC1155
        });

        vm.prank(marketplace);
        NFTTransferLib.TransferResult memory result = NFTTransferLib.transferNFT(params);

        assertFalse(result.success);
        assertTrue(bytes(result.errorMessage).length > 0);
    }
}
