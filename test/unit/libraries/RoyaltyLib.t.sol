// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/libraries/RoyaltyLib.sol";
import "src/common/Fee.sol";
import "src/common/BaseCollection.sol";
import "test/mocks/MockERC721.sol";
import "test/mocks/MockERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title RoyaltyLibTest
 * @notice Comprehensive test suite for RoyaltyLib library
 * @dev Tests all functions, edge cases, and error conditions to achieve >90% coverage
 */
contract RoyaltyLibTest is Test {
    using RoyaltyLib for RoyaltyLib.RoyaltyParams;

    // Test contracts
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    Fee public feeContract;
    TestableBaseCollection public baseCollection;
    MockERC2981Contract public erc2981Contract;
    MockInvalidContract public invalidContract;

    // Test addresses
    address public constant OWNER = address(0x1);
    address public constant ROYALTY_RECEIVER = address(0x2);
    address public constant USER = address(0x3);

    // Test constants
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant SALE_PRICE = 1 ether;
    uint256 public constant ROYALTY_FEE = 500; // 5%
    uint256 public constant MAX_ROYALTY_RATE = 1000; // 10%

    function setUp() public {
        // Deploy test contracts
        mockERC721 = new MockERC721("Test NFT", "TNFT");
        mockERC1155 = new MockERC1155("Test ERC1155", "T1155");
        feeContract = new Fee(OWNER, ROYALTY_FEE);
        baseCollection = new TestableBaseCollection();
        erc2981Contract = new MockERC2981Contract();
        invalidContract = new MockInvalidContract();

        // Setup mock contracts
        vm.prank(OWNER);
        mockERC721.mint(USER, TOKEN_ID);

        vm.prank(OWNER);
        mockERC1155.mint(USER, TOKEN_ID, 1);

        // Setup base collection
        baseCollection.setRoyaltyFee(ROYALTY_FEE);
        baseCollection.setOwner(ROYALTY_RECEIVER);
    }

    // ============================================================================
    // MAIN FUNCTION TESTS
    // ============================================================================

    function test_GetRoyaltyInfo_FeeContract_Success() public {
        // MockERC721 has ERC2981 from constructor which takes precedence
        // ERC2981 is set to 5% royalty to test contract (msg.sender) in constructor
        mockERC721.setFeeContract(address(feeContract));

        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(mockERC721), TOKEN_ID, SALE_PRICE, MAX_ROYALTY_RATE);

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertTrue(info.hasRoyalty);
        // ERC2981 takes precedence, returns test contract as receiver
        assertEq(info.receiver, address(this));
        assertEq(info.amount, (SALE_PRICE * ROYALTY_FEE) / 10000);
        assertEq(info.rate, ROYALTY_FEE);
        assertEq(info.source, "ERC2981"); // ERC2981 takes precedence over Fee contract
    }

    function test_GetRoyaltyInfo_BaseCollection_Success() public {
        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(baseCollection), TOKEN_ID, SALE_PRICE, MAX_ROYALTY_RATE);

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertTrue(info.hasRoyalty);
        assertEq(info.receiver, ROYALTY_RECEIVER);
        assertEq(info.amount, (SALE_PRICE * ROYALTY_FEE) / 10000);
        assertEq(info.rate, ROYALTY_FEE);
        assertEq(info.source, "BaseCollection");
    }

    function test_GetRoyaltyInfo_ERC2981_Success() public {
        // Setup ERC2981 contract
        erc2981Contract.setRoyaltyInfo(ROYALTY_RECEIVER, ROYALTY_FEE);

        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(erc2981Contract), TOKEN_ID, SALE_PRICE, MAX_ROYALTY_RATE);

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertTrue(info.hasRoyalty);
        assertEq(info.receiver, ROYALTY_RECEIVER);
        assertEq(info.amount, (SALE_PRICE * ROYALTY_FEE) / 10000);
        assertEq(info.rate, ROYALTY_FEE);
        assertEq(info.source, "ERC2981");
    }

    function test_GetRoyaltyInfo_NoRoyalty() public {
        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(invalidContract), TOKEN_ID, SALE_PRICE, MAX_ROYALTY_RATE);

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertFalse(info.hasRoyalty);
        assertEq(info.receiver, address(0));
        assertEq(info.amount, 0);
        assertEq(info.rate, 0);
        assertEq(info.source, "None");
    }

    function test_CalculateRoyalty_Success() public {
        mockERC721.setFeeContract(address(feeContract));

        (address receiver, uint256 royaltyAmount) =
            RoyaltyLib.calculateRoyalty(address(mockERC721), TOKEN_ID, SALE_PRICE);

        // MockERC721 has ERC2981 which takes precedence, returns test contract
        assertEq(receiver, address(this));
        assertEq(royaltyAmount, (SALE_PRICE * ROYALTY_FEE) / 10000);
    }

    function test_CalculateRoyalty_NoRoyalty() public {
        (address receiver, uint256 royaltyAmount) =
            RoyaltyLib.calculateRoyalty(address(invalidContract), TOKEN_ID, SALE_PRICE);

        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    // ============================================================================
    // EDGE CASES AND ERROR CONDITIONS
    // ============================================================================

    function test_GetRoyaltyInfo_ExceedsMaxRate() public {
        // Test 1: Fee contract constructor should revert on invalid fee
        vm.expectRevert(Fee__InvalidRoyaltyFee.selector);
        new Fee(OWNER, 1500); // 15% > 10% max - should revert

        // Test 2: Valid Fee contract but rate exceeds RoyaltyLib's maxRoyaltyRate parameter
        Fee validFee = new Fee(OWNER, 1000); // 10% - valid for Fee contract
        mockERC721.setFeeContract(address(validFee));

        // Use a lower maxRoyaltyRate in params (5%)
        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(mockERC721), TOKEN_ID, SALE_PRICE, 500); // 5% max

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        // Should return royalty from ERC2981 (5%) since it equals the max rate (5%)
        // The Fee contract's 10% is rejected, but ERC2981's 5% is accepted
        assertTrue(info.hasRoyalty);
        assertEq(info.source, "ERC2981");
        assertEq(info.rate, 500); // 5%
    }

    function test_GetRoyaltyInfo_ZeroSalePrice() public {
        mockERC721.setFeeContract(address(feeContract));

        RoyaltyLib.RoyaltyParams memory params = RoyaltyLib.createRoyaltyParams(
            address(mockERC721),
            TOKEN_ID,
            0, // Zero sale price
            MAX_ROYALTY_RATE
        );

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertTrue(info.hasRoyalty);
        assertEq(info.amount, 0); // Zero royalty amount
        assertEq(info.rate, ROYALTY_FEE);
    }

    function test_GetRoyaltyInfo_ZeroAddress() public {
        RoyaltyLib.RoyaltyParams memory params = RoyaltyLib.createRoyaltyParams(
            address(0), // Zero address
            TOKEN_ID,
            SALE_PRICE,
            MAX_ROYALTY_RATE
        );

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        assertFalse(info.hasRoyalty);
        assertEq(info.source, "None");
    }

    // ============================================================================
    // UTILITY FUNCTION TESTS
    // ============================================================================

    function test_CalculateRoyaltyAmount() public {
        uint256 royaltyAmount = RoyaltyLib.calculateRoyaltyAmount(SALE_PRICE, ROYALTY_FEE);
        assertEq(royaltyAmount, (SALE_PRICE * ROYALTY_FEE) / 10000);
    }

    function test_CalculateRoyaltyAmount_ZeroPrice() public {
        uint256 royaltyAmount = RoyaltyLib.calculateRoyaltyAmount(0, ROYALTY_FEE);
        assertEq(royaltyAmount, 0);
    }

    function test_CalculateRoyaltyAmount_ZeroRate() public {
        uint256 royaltyAmount = RoyaltyLib.calculateRoyaltyAmount(SALE_PRICE, 0);
        assertEq(royaltyAmount, 0);
    }

    function test_CreateRoyaltyParams() public {
        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(mockERC721), TOKEN_ID, SALE_PRICE, MAX_ROYALTY_RATE);

        assertEq(params.nftContract, address(mockERC721));
        assertEq(params.tokenId, TOKEN_ID);
        assertEq(params.salePrice, SALE_PRICE);
        assertEq(params.maxRoyaltyRate, MAX_ROYALTY_RATE);
    }

    // ============================================================================
    // FUZZ TESTS
    // ============================================================================

    function testFuzz_CalculateRoyaltyAmount(uint256 salePrice, uint256 royaltyRate) public {
        // Bound inputs to reasonable ranges
        salePrice = bound(salePrice, 0, type(uint128).max);
        royaltyRate = bound(royaltyRate, 0, 10000); // 0-100%

        uint256 royaltyAmount = RoyaltyLib.calculateRoyaltyAmount(salePrice, royaltyRate);

        // Verify calculation
        assertEq(royaltyAmount, (salePrice * royaltyRate) / 10000);

        // Verify royalty doesn't exceed sale price
        assertLe(royaltyAmount, salePrice);
    }

    function testFuzz_GetRoyaltyInfo_ValidInputs(uint256 salePrice, uint256 maxRoyaltyRate, uint256 tokenId) public {
        // Bound inputs
        salePrice = bound(salePrice, 1, type(uint128).max);
        maxRoyaltyRate = bound(maxRoyaltyRate, 100, 10000); // 1-100%
        tokenId = bound(tokenId, 1, type(uint128).max);

        mockERC721.setFeeContract(address(feeContract));

        RoyaltyLib.RoyaltyParams memory params =
            RoyaltyLib.createRoyaltyParams(address(mockERC721), tokenId, salePrice, maxRoyaltyRate);

        RoyaltyLib.RoyaltyInfo memory info = RoyaltyLib.getRoyaltyInfo(params);

        if (ROYALTY_FEE <= maxRoyaltyRate) {
            assertTrue(info.hasRoyalty);
            assertEq(info.amount, (salePrice * ROYALTY_FEE) / 10000);
        }
    }
}

// ============================================================================
// MOCK CONTRACTS FOR TESTING
// ============================================================================

/**
 * @title TestableBaseCollection
 * @notice Mock BaseCollection for testing
 */
contract TestableBaseCollection {
    uint256 private royaltyFee;
    address private collectionOwner;

    function setRoyaltyFee(uint256 _royaltyFee) external {
        royaltyFee = _royaltyFee;
    }

    function getRoyaltyFee() external view returns (uint256) {
        return royaltyFee;
    }

    function setOwner(address _owner) external {
        collectionOwner = _owner;
    }

    function owner() external view returns (address) {
        return collectionOwner;
    }
}

/**
 * @title MockERC2981Contract
 * @notice Mock contract implementing ERC2981
 */
contract MockERC2981Contract is IERC2981 {
    address private royaltyReceiver;
    uint256 private royaltyRate;

    function setRoyaltyInfo(address _receiver, uint256 _rate) external {
        royaltyReceiver = _receiver;
        royaltyRate = _rate;
    }

    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (royaltyReceiver, (salePrice * royaltyRate) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC2981).interfaceId;
    }
}

/**
 * @title MockInvalidContract
 * @notice Mock contract that doesn't implement any royalty standards
 */
contract MockInvalidContract {
    // Empty contract for testing fallback behavior

    }
