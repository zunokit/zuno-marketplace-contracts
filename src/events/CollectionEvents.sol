// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MintStage} from "src/types/ListingTypes.sol";

event Minted(address indexed to, uint256 indexed tokenId, uint256 amount);

event BatchMinted(address indexed to, uint256 amount);

event StageUpdated(MintStage stage, uint256 timestamp);

event ERC721CollectionCreated(address indexed collectionAddress, address indexed creator);

event ERC1155CollectionCreated(address indexed collectionAddress, address indexed creator);

/**
 * @notice Emitted when allowlist is setup with addresses and allowlist-only mode
 * @param addresses Array of addresses added to allowlist
 * @param allowlistOnly Whether allowlist-only mode is enabled
 */
event AllowlistSetup(address[] addresses, bool allowlistOnly);
