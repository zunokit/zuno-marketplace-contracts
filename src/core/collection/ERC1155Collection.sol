// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseCollection} from "src/common/BaseCollection.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";
import {Minted, BatchMinted} from "src/events/CollectionEvents.sol";
import "src/errors/CollectionErrors.sol";

contract ERC1155Collection is ERC1155, BaseCollection, IERC2981 {
    // Collection metadata
    string private s_name;
    string private s_symbol;

    constructor(CollectionParams memory params) ERC1155(params.tokenURI) BaseCollection(params) {
        s_name = params.name;
        s_symbol = params.symbol;
    }

    // Add name and symbol functions for compatibility with frontend
    function name() public view returns (string memory) {
        return s_name;
    }

    function symbol() public view returns (string memory) {
        return s_symbol;
    }

    // Internal function to set name and symbol for proxy initialization
    function _setNameAndSymbol(string memory _name, string memory _symbol) internal {
        s_name = _name;
        s_symbol = _symbol;
    }

    // Mint a single NFT
    function mint(address to, uint256 amount) external payable {
        // checkMint now auto-updates stage internally
        uint256 requiredPayment = checkMint(to, amount);
        if (msg.value < requiredPayment) {
            revert Collection__InsufficientPayment();
        }

        uint256 tokenId = s_tokenIdCounter + 1;
        s_tokenIdCounter = tokenId;
        s_totalMinted += amount;
        s_mintedPerWallet[to] += amount;

        _mint(to, tokenId, amount, "");

        emit Minted(to, tokenId, amount);
    }

    // Batch mint NFTs
    function batchMintERC1155(address to, uint256 amount) external payable {
        // checkMint now auto-updates stage internally
        uint256 requiredPayment = checkMint(to, amount);
        if (msg.value < requiredPayment) {
            revert Collection__InsufficientPayment();
        }

        _batchMint(to, amount);
        emit BatchMinted(to, amount);
    }

    function _batchMint(address to, uint256 amount) internal {
        uint256 startTokenId = s_tokenIdCounter;
        uint256[] memory ids = new uint256[](amount);
        uint256[] memory values = new uint256[](amount);

        // Fill arrays
        for (uint256 i = 0; i < amount; i++) {
            ids[i] = startTokenId + i + 1;
            values[i] = 1;
        }

        // Update state
        s_tokenIdCounter = startTokenId + amount;
        s_totalMinted += amount;
        s_mintedPerWallet[to] += amount;

        // Perform batch mint
        _mintBatch(to, ids, values, "");
    }

    /**
     * @notice Mint NFTs as owner (bypasses all restrictions except maxSupply)
     * @param to Address to receive the minted NFT(s)
     * @param amount Number of NFTs to mint
     * @dev Only callable by collection owner
     * @dev Bypasses: payment requirements, timing restrictions, allowlist, per-wallet limits
     * @dev Still respects maxSupply limit
     */
    function ownerMint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert Collection__InvalidAmount();
        if (to == address(0)) revert Collection__InvalidAddress();

        // Check max supply limit
        if (s_totalMinted + amount > s_maxSupply) {
            revert Collection__MintLimitExceeded();
        }

        // Use the batch mint function since it already handles amount correctly
        _batchMint(to, amount);
        emit BatchMinted(to, amount);
    }

    // Override uri to resolve conflict between ERC1155 and ERC1155URIStorage
    function uri(uint256 tokenId) public view override(ERC1155) returns (string memory) {
        return super.uri(tokenId);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return s_feeContract.royaltyInfo(tokenId, salePrice);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
