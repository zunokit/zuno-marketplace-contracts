// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title  MerkleAllowlistLib
 * @notice Helpers for verifying Merkle-tree based allowlists.
 *
 * @dev    Storing allowlists as `mapping(address => bool)` does not scale —
 *         enrolling 10k addresses costs 10k `SSTORE` operations and is hard
 *         to mutate without resetting everyone.
 *
 *         This library lets a collection store a single `bytes32 merkleRoot`
 *         and have minters present a proof generated off-chain. We expose
 *         two leaf shapes that we use in production:
 *
 *           1. Boolean allowlist          – leaf is `keccak256(abi.encode(addr))`
 *           2. Per-address quota allowlist – leaf is
 *                `keccak256(abi.encode(addr, maxMint))`
 *
 *         Leaves are double-hashed (per OpenZeppelin's
 *         standardNodeHash recommendation) to make malleability/second-preimage
 *         attacks infeasible regardless of tree depth.
 */
library MerkleAllowlistLib {
    /**
     * @notice Build the canonical double-hashed leaf for a boolean allowlist.
     * @param  account Address being enrolled.
     * @return leaf    `keccak256(bytes.concat(keccak256(abi.encode(account))))`.
     */
    function leafForAccount(address account) internal pure returns (bytes32 leaf) {
        leaf = keccak256(bytes.concat(keccak256(abi.encode(account))));
    }

    /**
     * @notice Build the canonical double-hashed leaf for a quota allowlist.
     * @param  account Address being enrolled.
     * @param  maxMint Maximum number of items `account` is allowed to mint.
     * @return leaf    Double-hashed leaf.
     */
    function leafForQuota(address account, uint256 maxMint) internal pure returns (bytes32 leaf) {
        leaf = keccak256(bytes.concat(keccak256(abi.encode(account, maxMint))));
    }

    /**
     * @notice Verify that `account` is in the boolean allowlist identified by
     *         `root`.
     * @dev    Returns `false` when the root is zero so callers do not have to
     *         add a separate "allowlist disabled" branch.
     */
    function verifyAccount(
        address account,
        bytes32 root,
        bytes32[] calldata proof
    ) internal pure returns (bool) {
        if (root == bytes32(0)) return false;
        return MerkleProof.verifyCalldata(proof, root, leafForAccount(account));
    }

    /**
     * @notice Verify that `account` is enrolled with quota `maxMint` in the
     *         allowlist identified by `root`.
     */
    function verifyQuota(
        address account,
        uint256 maxMint,
        bytes32 root,
        bytes32[] calldata proof
    ) internal pure returns (bool) {
        if (root == bytes32(0)) return false;
        return MerkleProof.verifyCalldata(proof, root, leafForQuota(account, maxMint));
    }
}
