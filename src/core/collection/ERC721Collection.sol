// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BaseCollection} from "src/common/BaseCollection.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {CollectionParams} from "src/types/ListingTypes.sol";
import {Minted, BatchMinted} from "src/events/CollectionEvents.sol";
import "src/errors/CollectionErrors.sol";

contract ERC721Collection is ERC721, BaseCollection, IERC2981 {
    // Collection metadata - stored separately for proxy pattern compatibility
    string private s_collectionName;
    string private s_collectionSymbol;

    constructor(CollectionParams memory params) ERC721(params.name, params.symbol) BaseCollection(params) {
        s_collectionName = params.name;
        s_collectionSymbol = params.symbol;
    }

    // Override name() to return our stored value (needed for proxy pattern)
    function name() public view override returns (string memory) {
        return s_collectionName;
    }

    // Override symbol() to return our stored value (needed for proxy pattern)
    function symbol() public view override returns (string memory) {
        return s_collectionSymbol;
    }

    // Internal function to set name and symbol for proxy initialization
    function _setNameAndSymbol(string memory _name, string memory _symbol) internal {
        s_collectionName = _name;
        s_collectionSymbol = _symbol;
    }

    function mint(address to) external payable {
        // checkMint now auto-updates stage internally
        uint256 requiredPayment = checkMint(to, 1);
        if (msg.value < requiredPayment) {
            revert Collection__InsufficientPayment();
        }
        s_tokenIdCounter++;
        _mintWithURI(to, s_tokenIdCounter);
    }

    function batchMintERC721(address to, uint256 amount) external payable {
        // checkMint now auto-updates stage internally
        uint256 requiredPayment = checkMint(to, amount);
        if (msg.value < requiredPayment) {
            revert Collection__InsufficientPayment();
        }
        _batchMint(to, amount);
    }

    /**
     * @notice Owner-only mint function - bypasses payment, timing, allowlist, and per-wallet limits
     * @param to Address to mint to
     * @param amount Number of tokens to mint
     * @dev Only respects maxSupply limit for safety
     */
    function ownerMint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert Collection__InvalidAmount();
        if (s_totalMinted + amount > s_maxSupply) {
            revert Collection__MintLimitExceeded();
        }
        _batchMint(to, amount);
    }

    function _batchMint(address to, uint256 amount) internal {
        uint256 startId = s_tokenIdCounter;
        s_tokenIdCounter += amount;

        for (uint256 i = 0; i < amount; i++) {
            _mintWithURI(to, startId + i + 1);
        }
        emit BatchMinted(to, amount);
    }

    function _mintWithURI(address to, uint256 tokenId) internal {
        s_mintedPerWallet[to]++;
        s_totalMinted++;
        _mint(to, tokenId);
        emit Minted(to, tokenId, 1);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(s_tokenURI, "/", Strings.toString(tokenId), ".json"));
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return s_feeContract.royaltyInfo(tokenId, salePrice);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
