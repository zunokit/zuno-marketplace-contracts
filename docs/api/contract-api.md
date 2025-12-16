# Contract API Reference

## NFT Exchanges

The marketplace uses separate exchanges for ERC721 and ERC1155 tokens. Listings are identified by `bytes32 listingId`.

### ERC721 Exchange

#### `listNFT`

```solidity
function listNFT(
    address nftContract,
    uint256 tokenId,
    uint256 price,
    uint256 listingDuration
) public
```

Creates a fixed-price listing for a single ERC721 token.

#### `batchListNFT`

```solidity
function batchListNFT(
    address nftContract,
    uint256[] memory tokenIds,
    uint256[] memory prices,
    uint256 listingDuration
) public
```

Batch list multiple ERC721 tokens from the same collection.

#### `buyNFT`

```solidity
function buyNFT(bytes32 listingId) public payable
```

Purchases the ERC721 listing. Must send exact price.

#### Events

```solidity
event NFTListed(bytes32 listingId, address nftContract, uint256 tokenId, address seller, uint256 price);
```

### ERC1155 Exchange

#### `buyNFT` (full amount)

```solidity
function buyNFT(bytes32 listingId) public payable
```

Purchases the entire ERC1155 listing amount.

#### `buyNFT` (partial amount)

```solidity
function buyNFT(bytes32 listingId, uint256 amount) public payable
```

Purchases a partial amount from an ERC1155 listing.

#### Events

```solidity
event NFTListed(bytes32 listingId, address nftContract, uint256 tokenId, address seller, uint256 price);
```

### Common Notes

- `listingId` is generated as `keccak256(abi.encodePacked(contractAddress, tokenId, seller, block.timestamp))`.
- Ownership and approval are validated prior to listing via `NFTValidationLib`.
- Platform and royalty fees are calculated by the FeeRegistry (see registries section) or via `UserHub.calculateFees`.

---

[To be expanded with all functions]
