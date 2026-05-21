// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {GasOptimizedLibrary} from "src/optimizations/GasOptimizedLibrary.sol";

/**
 * @title GasOptimizedLibraryTest
 * @notice Unit tests for GasOptimizedLibrary helpers
 * @dev Library uses inline assembly; tests pin the expected behavior by
 *      comparing each helper to its idiomatic Solidity equivalent.
 */
contract GasOptimizedLibraryHarness {
    function efficientHash(bytes memory data) external pure returns (bytes32) {
        return GasOptimizedLibrary.efficientHash(data);
    }

    function hashAddressesAndValue(address a, address b, uint256 v) external pure returns (bytes32) {
        return GasOptimizedLibrary.hashAddressesAndValue(a, b, v);
    }

    function generateOptimizedListingId(address c, uint256 tokenId, address seller, uint256 t)
        external
        pure
        returns (bytes32)
    {
        return GasOptimizedLibrary.generateOptimizedListingId(c, tokenId, seller, t);
    }

    function efficientTransfer(address to, uint256 amount) external returns (bool) {
        return GasOptimizedLibrary.efficientTransfer(to, amount);
    }

    function calculateFeeOptimized(uint256 amount, uint256 feeBps) external pure returns (uint256) {
        return GasOptimizedLibrary.calculateFeeOptimized(amount, feeBps);
    }

    receive() external payable {}
}

/// @notice Reverts when receiving ETH; used to test efficientTransfer failure path.
contract Rejector {
    fallback() external payable {
        revert("nope");
    }
}

contract GasOptimizedLibraryTest is Test {
    GasOptimizedLibraryHarness internal h;

    function setUp() public {
        h = new GasOptimizedLibraryHarness();
    }

    // ============================================================
    // efficientHash
    // ============================================================

    function test_efficientHash_matchesKeccak256_emptyBytes() public {
        bytes memory data = "";
        assertEq(h.efficientHash(data), keccak256(data));
    }

    function test_efficientHash_matchesKeccak256_smallBytes() public {
        bytes memory data = bytes("zuno");
        assertEq(h.efficientHash(data), keccak256(data));
    }

    function testFuzz_efficientHash_matchesKeccak256(bytes memory data) public {
        assertEq(h.efficientHash(data), keccak256(data));
    }

    // ============================================================
    // hashAddressesAndValue
    // ============================================================

    function test_hashAddressesAndValue_isDeterministic() public {
        address a = address(0x1111111111111111111111111111111111111111);
        address b = address(0x2222222222222222222222222222222222222222);
        uint256 v = 42;
        bytes32 first = h.hashAddressesAndValue(a, b, v);
        bytes32 second = h.hashAddressesAndValue(a, b, v);
        assertEq(first, second);
    }

    function test_hashAddressesAndValue_isOrderSensitive() public {
        address a = address(0x1111111111111111111111111111111111111111);
        address b = address(0x2222222222222222222222222222222222222222);
        assertTrue(h.hashAddressesAndValue(a, b, 1) != h.hashAddressesAndValue(b, a, 1));
    }

    function testFuzz_hashAddressesAndValue_changesWithValue(address a, address b, uint256 v1, uint256 v2) public {
        vm.assume(v1 != v2);
        assertTrue(h.hashAddressesAndValue(a, b, v1) != h.hashAddressesAndValue(a, b, v2));
    }

    // ============================================================
    // generateOptimizedListingId
    // ============================================================

    function test_generateOptimizedListingId_changesWithEachInput() public {
        address c = makeAddr("collection");
        address s = makeAddr("seller");
        bytes32 base = h.generateOptimizedListingId(c, 1, s, 100);

        // Each component changing must produce a different id.
        assertTrue(base != h.generateOptimizedListingId(c, 2, s, 100));
        assertTrue(base != h.generateOptimizedListingId(address(uint160(c) + 1), 1, s, 100));
        assertTrue(base != h.generateOptimizedListingId(c, 1, address(uint160(s) + 1), 100));
        assertTrue(base != h.generateOptimizedListingId(c, 1, s, 101));
    }

    // ============================================================
    // efficientTransfer
    // ============================================================

    function test_efficientTransfer_movesETHToEOA() public {
        vm.deal(address(h), 5 ether);
        address payable to = payable(address(0xCAfe));
        uint256 startBalance = to.balance;

        bool ok = h.efficientTransfer(to, 1 ether);

        assertTrue(ok);
        assertEq(to.balance, startBalance + 1 ether);
        assertEq(address(h).balance, 4 ether);
    }

    function test_efficientTransfer_returnsFalseWhenRecipientReverts() public {
        Rejector r = new Rejector();
        vm.deal(address(h), 1 ether);

        bool ok = h.efficientTransfer(address(r), 0.1 ether);

        assertFalse(ok);
        // ETH should not have moved.
        assertEq(address(r).balance, 0);
        assertEq(address(h).balance, 1 ether);
    }

    // ============================================================
    // calculateFeeOptimized
    // ============================================================

    function test_calculateFeeOptimized_zeroBps_returnsZero() public {
        assertEq(h.calculateFeeOptimized(1 ether, 0), 0);
    }

    function test_calculateFeeOptimized_fiveHundredBps_isFivePercent() public {
        // 500 bps = 5%
        assertEq(h.calculateFeeOptimized(1_000_000, 500), 50_000);
    }

    function test_calculateFeeOptimized_tenThousandBps_isFullAmount() public {
        // 10000 bps = 100%
        assertEq(h.calculateFeeOptimized(123_456, 10_000), 123_456);
    }

    function testFuzz_calculateFeeOptimized_matchesIdiomatic(uint128 amount, uint16 feeBps) public {
        vm.assume(feeBps <= 10_000);
        uint256 expected = (uint256(amount) * uint256(feeBps)) / 10_000;
        assertEq(h.calculateFeeOptimized(uint256(amount), uint256(feeBps)), expected);
    }
}
