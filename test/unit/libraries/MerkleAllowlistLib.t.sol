// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {MerkleAllowlistLib} from "src/libraries/MerkleAllowlistLib.sol";

/// @dev Minimal external surface so we can call calldata-style functions in tests.
contract MerkleAllowlistHarness {
    function leafForAccount(address account) external pure returns (bytes32) {
        return MerkleAllowlistLib.leafForAccount(account);
    }

    function leafForQuota(address account, uint256 maxMint) external pure returns (bytes32) {
        return MerkleAllowlistLib.leafForQuota(account, maxMint);
    }

    function verifyAccount(
        address account,
        bytes32 root,
        bytes32[] calldata proof
    ) external pure returns (bool) {
        return MerkleAllowlistLib.verifyAccount(account, root, proof);
    }

    function verifyQuota(
        address account,
        uint256 maxMint,
        bytes32 root,
        bytes32[] calldata proof
    ) external pure returns (bool) {
        return MerkleAllowlistLib.verifyQuota(account, maxMint, root, proof);
    }
}

contract MerkleAllowlistLibTest is Test {
    MerkleAllowlistHarness internal harness;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCAFE);
    address internal mallory = address(0xBAD);

    function setUp() public {
        harness = new MerkleAllowlistHarness();
    }

    // ---------------------------------------------------------------
    // helpers — build a balanced 4-leaf tree using the same double-hash leaf
    // shape the library uses; intermediate nodes use the standard OZ sort+hash.
    // ---------------------------------------------------------------

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function _buildAccountTree(address[4] memory accounts)
        internal
        view
        returns (bytes32 root, bytes32[4] memory leaves)
    {
        for (uint256 i; i < 4; ++i) {
            leaves[i] = harness.leafForAccount(accounts[i]);
        }
        bytes32 left = _hashPair(leaves[0], leaves[1]);
        bytes32 right = _hashPair(leaves[2], leaves[3]);
        root = _hashPair(left, right);
    }

    function _accountProofForIndex(bytes32[4] memory leaves, uint256 index)
        internal
        pure
        returns (bytes32[] memory proof)
    {
        proof = new bytes32[](2);
        if (index == 0) {
            proof[0] = leaves[1];
            proof[1] = _hashPair(leaves[2], leaves[3]);
        } else if (index == 1) {
            proof[0] = leaves[0];
            proof[1] = _hashPair(leaves[2], leaves[3]);
        } else if (index == 2) {
            proof[0] = leaves[3];
            proof[1] = _hashPair(leaves[0], leaves[1]);
        } else {
            proof[0] = leaves[2];
            proof[1] = _hashPair(leaves[0], leaves[1]);
        }
    }

    // ---------------------------------------------------------------
    // leafForAccount / leafForQuota
    // ---------------------------------------------------------------

    function test_LeafForAccountIsDeterministicAndUnique() public view {
        bytes32 a = harness.leafForAccount(alice);
        bytes32 b = harness.leafForAccount(alice);
        bytes32 c = harness.leafForAccount(bob);

        assertEq(a, b, "same address must produce the same leaf");
        assertTrue(a != c, "different addresses must produce different leaves");
    }

    function test_LeafForQuotaDependsOnQuota() public view {
        bytes32 q1 = harness.leafForQuota(alice, 1);
        bytes32 q2 = harness.leafForQuota(alice, 2);
        assertTrue(q1 != q2, "different quotas must produce different leaves");
    }

    function test_AccountLeafDiffersFromQuotaLeaf() public view {
        bytes32 a = harness.leafForAccount(alice);
        bytes32 q = harness.leafForQuota(alice, 1);
        assertTrue(a != q, "namespaces must be disjoint to prevent leaf reuse");
    }

    // ---------------------------------------------------------------
    // verifyAccount
    // ---------------------------------------------------------------

    function test_VerifyAccount_AcceptsValidProof() public view {
        address[4] memory accounts = [alice, bob, carol, address(0xD00D)];
        (bytes32 root, bytes32[4] memory leaves) = _buildAccountTree(accounts);

        for (uint256 i; i < 4; ++i) {
            bytes32[] memory proof = _accountProofForIndex(leaves, i);
            assertTrue(
                harness.verifyAccount(accounts[i], root, proof),
                "valid proof must verify"
            );
        }
    }

    function test_VerifyAccount_RejectsNonEnrolledAddress() public view {
        address[4] memory accounts = [alice, bob, carol, address(0xD00D)];
        (bytes32 root, bytes32[4] memory leaves) = _buildAccountTree(accounts);

        bytes32[] memory proofForAlice = _accountProofForIndex(leaves, 0);
        assertFalse(
            harness.verifyAccount(mallory, root, proofForAlice),
            "address must not satisfy a proof built for someone else"
        );
    }

    function test_VerifyAccount_RejectsTamperedProof() public view {
        address[4] memory accounts = [alice, bob, carol, address(0xD00D)];
        (bytes32 root, bytes32[4] memory leaves) = _buildAccountTree(accounts);

        bytes32[] memory proof = _accountProofForIndex(leaves, 0);
        proof[0] = bytes32(uint256(proof[0]) ^ uint256(1));

        assertFalse(harness.verifyAccount(alice, root, proof));
    }

    function test_VerifyAccount_RejectsZeroRoot() public view {
        bytes32[] memory empty = new bytes32[](0);
        assertFalse(harness.verifyAccount(alice, bytes32(0), empty));
    }

    // ---------------------------------------------------------------
    // verifyQuota
    // ---------------------------------------------------------------

    function test_VerifyQuota_AcceptsValidProofWithMatchingQuota() public view {
        bytes32 leafAlice2 = harness.leafForQuota(alice, 2);
        bytes32 leafBob1 = harness.leafForQuota(bob, 1);
        bytes32 root = _hashPair(leafAlice2, leafBob1);

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = leafBob1;

        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = leafAlice2;

        assertTrue(harness.verifyQuota(alice, 2, root, aliceProof));
        assertTrue(harness.verifyQuota(bob, 1, root, bobProof));
    }

    function test_VerifyQuota_RejectsWrongQuota() public view {
        bytes32 leafAlice2 = harness.leafForQuota(alice, 2);
        bytes32 leafBob1 = harness.leafForQuota(bob, 1);
        bytes32 root = _hashPair(leafAlice2, leafBob1);

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = leafBob1;

        assertFalse(
            harness.verifyQuota(alice, 3, root, aliceProof),
            "wrong quota must not verify even with valid sibling"
        );
    }

    function test_VerifyQuota_RejectsZeroRoot() public view {
        bytes32[] memory empty = new bytes32[](0);
        assertFalse(harness.verifyQuota(alice, 1, bytes32(0), empty));
    }
}
