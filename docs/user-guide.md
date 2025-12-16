# 🔗 Zuno Marketplace - Complete Frontend Integration Guide

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Contract Addresses](#-contract-addresses)
- [Core Functions](#-core-functions)
  - [NFT Listing & Trading](#1-listing-nfts)
  - [Auction System](#3-auctions)
  - [Offer System](#4-offers)
  - [Bundle Trading](#5-bundles)
  - [Collection Management](#7-collection-management)
- [Advanced Features](#-advanced-features)
  - [Fee Management](#fee-management)
  - [Royalty System](#royalty-system)
  - [Access Control](#access-control)
  - [Emergency Controls](#emergency-controls)
  - [Listing Validation](#listing-validation)
  - [Collection Verification](#collection-verification)
  - [History & Analytics](#history--analytics)
- [Events](#-events)
- [Error Handling](#-error-handling)
- [TypeScript Integration](#typescript-integration)
- [Best Practices](#best-practices)

## 🚀 Quick Start

### 1. Initialize with UserHub (Frontend)

Frontend only needs **ONE** contract address:

```javascript
// This is the ONLY address you need to store for users
const USER_HUB = '0x...'; // Get from deployment output

// Initialize user hub (for frontend/user operations)
const userHub = new ethers.Contract(USER_HUB, UserHubABI, provider);

// Get all core contract addresses from UserHub
const [
  erc721Exchange,
  erc1155Exchange,
  erc721Factory,
  erc1155Factory,
  englishAuction,
  dutchAuction,
  auctionFactory,
  feeRegistry,
  bundleManager,
  offerManager
] = await userHub.getAllAddresses();

// ⚠️ Additional contracts (not in getAllAddresses yet)
// Now you can get them via dedicated getter functions:
const listingValidator = await userHub.getListingValidator();
const emergencyManager = await userHub.getEmergencyManager();
const accessControl = await userHub.getAccessControl();
const historyTracker = await userHub.getHistoryTracker();

// OR get all additional addresses at once
const [
  listingValidatorAddr,
  emergencyManagerAddr,
  accessControlAddr,
  historyTrackerAddr
] = await userHub.getAdditionalAddresses();

// Helper functions from UserHub
const feeRegistryAddr = await userHub.getFeeRegistry();
const erc721FactoryAddr = await userHub.getFactoryFor('ERC721');
const englishAuctionAddr = await userHub.getAuctionFor(0); // 0 = ENGLISH
const dutchAuctionAddr = await userHub.getAuctionFor(1); // 1 = DUTCH

// Auto-detect exchange for any NFT
const nftExchange = await userHub.getExchangeFor(nftContractAddress);

// Check system status
const [isHealthy, activeContracts, timestamp] = await userHub.getSystemStatus();
```

**⚠️ Important Note:**
UserHub provides two main functions for getting contract addresses:

1. **`getAllAddresses()`** - Returns 10 core contracts:

   - ERC721 Exchange
   - ERC1155 Exchange
   - ERC721 Factory
   - ERC1155 Factory
   - English Auction
   - Dutch Auction
   - Auction Factory
   - Fee Registry
   - Bundle Manager
   - Offer Manager

2. **`getAdditionalAddresses()`** - Returns 4 additional contracts:
   - Listing Validator
   - Emergency Manager
   - Access Control
   - History Tracker

**Not available via UserHub:**

- `advancedFeeManager` - ❌ Query FeeRegistry instead
- `marketplaceValidator` - ❌ Deploy separately and store address

### 2. AdminHub (Admin Operations Only)

**⚠️ Admin-only operations** - requires admin role:

```javascript
// Admin operations require AdminHub address and admin role
const ADMIN_HUB = '0x...'; // Get from deployment output

// Initialize admin hub (requires admin wallet/signer)
const adminHub = new ethers.Contract(ADMIN_HUB, AdminHubABI, adminSigner);

// Register new exchange (admin only)
await adminHub.registerExchange(
  IExchangeRegistry.TokenStandard.ERC721,
  newExchangeAddress
);

// Register new collection factory (admin only)
await adminHub.registerCollectionFactory('ERC721', newFactoryAddress);

// Register auction contracts (admin only)
await adminHub.registerAuction(
  IAuctionRegistry.AuctionType.ENGLISH,
  englishAuctionAddress
);

// Emergency pause (admin only)
await adminHub.emergencyPause();
```

### 3. Automatic Exchange Detection

```javascript
// UserHub automatically detects which exchange to use
const exchangeAddress = await userHub.getExchangeFor(nftContract);
const exchange = new ethers.Contract(exchangeAddress, ExchangeABI, signer);
```

## 📍 Contract Addresses

After deployment, you'll get:

```
UserHub: 0x... (SAVE THIS!)
AdminHub: 0x... (Admin operations)
```

All other addresses can be retrieved via UserHub:

```javascript
// Get individual addresses
const erc721Exchange = await hub.getERC721Exchange();
const erc1155Exchange = await hub.getERC1155Exchange();
const offerManager = await hub.getOfferManager();
const bundleManager = await hub.getBundleManager();
```

## 🔧 Core Functions

### 1. Listing NFTs

**Step 1: Get Exchange Address from UserHub**

```javascript
// Initialize UserHub first (ONE TIME ONLY)
const userHub = new ethers.Contract(USER_HUB, UserHubABI, provider);

// Get exchange address for your NFT
const exchangeAddress = await userHub.getExchangeFor(nftContract);

// OR get specific exchange
const [erc721Exchange, erc1155Exchange] = await userHub.getAllAddresses();
```

**Step 2: List NFT**

#### Fixed Price Listing (ERC721)

```javascript
// Connect to exchange
const exchange = new ethers.Contract(exchangeAddress, ExchangeABI, signer);

// 1. Approve marketplace
await nft.approve(exchangeAddress, tokenId);

// 2. List NFT
await exchange.listNFT(
  nftContract, // NFT contract address
  tokenId, // Token ID
  price, // Price in wei
  duration // Listing duration in seconds
);

// Get listing ID
const listingId = await exchange.getGeneratedListingId(
  nftContract,
  tokenId,
  seller
);
```

#### Batch Listing (ERC721)

```javascript
// Approve all
await nft.setApprovalForAll(exchangeAddress, true);

// Batch list
await exchange.batchListNFT(
  nftContract, // NFT contract address
  tokenIds, // Array of token IDs
  prices, // Array of prices
  duration // Same duration for all
);
```

#### ERC1155 Listing

```javascript
// Approve
await nft1155.setApprovalForAll(exchangeAddress, true);

// List with amount
await erc1155Exchange.listNFT(
  nftContract,
  tokenId,
  amount, // Number of tokens to list
  pricePerToken, // Price per token
  duration
);
```

### 2. Buying NFTs

#### Direct Purchase

```javascript
// Calculate fees first
const fees = await hub.calculateFees(nftContract, tokenId, price);
const totalPrice = fees.totalPrice; // Includes platform fee & royalty

// Buy NFT
await exchange.buyNFT(listingId, {
  value: totalPrice
});
```

#### Batch Purchase

```javascript
// Get batch price
const breakdown = await exchange.getBatchPriceBreakdown(listingIds);
const totalPrice = breakdown.totalPrice;

// Buy multiple
await exchange.batchBuyNFT(listingIds, {
  value: totalPrice
});
```

### 3. Auctions

#### Create English Auction

```javascript
const auctionFactory = new ethers.Contract(
  auctionFactoryAddress,
  FactoryABI,
  signer
);

// Approve NFT
await nft.approve(auctionFactoryAddress, tokenId);

// Create auction
const tx = await auctionFactory.createEnglishAuction(
  nftContract,
  tokenId,
  amount, // 1 for ERC721
  startingPrice, // Minimum bid
  reservePrice, // Optional reserve (0 for none)
  duration // Auction duration
);

// Get auction ID from event
const receipt = await tx.wait();
const auctionId = receipt.events[0].args.auctionId;
```

#### Place Bid (English)

```javascript
const englishAuction = new ethers.Contract(
  englishAuctionAddress,
  AuctionABI,
  signer
);

await englishAuction.placeBid(auctionId, {
  value: bidAmount
});
```

#### Create Dutch Auction

```javascript
await auctionFactory.createDutchAuction(
  nftContract,
  tokenId,
  amount,
  startingPrice, // High starting price
  endingPrice, // Low ending price
  duration // Price decrease duration
);
```

#### Buy Dutch Auction

```javascript
const dutchAuction = new ethers.Contract(
  dutchAuctionAddress,
  AuctionABI,
  signer
);

// Get current price
const currentPrice = await dutchAuction.getCurrentPrice(auctionId);

// Buy at current price
await dutchAuction.buyNow(auctionId, {
  value: currentPrice
});
```

### 4. Offers

#### Make Offer on NFT

```javascript
const offerManager = new ethers.Contract(offerManagerAddress, OfferABI, signer);

// ETH offer
const offerId = await offerManager.createNFTOffer(
  collection,
  tokenId,
  offerAmount,
  duration,
  {
    value: offerAmount // Lock ETH
  }
);

// ERC20 offer (approve token first)
await token.approve(offerManagerAddress, offerAmount);
await offerManager.createNFTOfferWithToken(
  collection,
  tokenId,
  offerAmount,
  tokenAddress,
  duration
);
```

#### Accept Offer

```javascript
// As NFT owner
await nft.approve(offerManagerAddress, tokenId);
await offerManager.acceptNFTOffer(offerId);
```

#### Collection Offer

```javascript
// Make offer on any NFT in collection
await offerManager.createCollectionOffer(
  collection,
  paymentToken, // address(0) for ETH
  pricePerNFT,
  quantity, // How many NFTs you want (max 100)
  expiration, // Unix timestamp
  {
    value: pricePerNFT * quantity // Only if ETH
  }
);
```

#### Trait-Based Offer

```javascript
// Make offer on NFTs with specific traits
await offerManager.createTraitOffer(
  collection,
  'Background', // trait type
  'Blue', // trait value
  paymentToken, // address(0) for ETH
  pricePerNFT,
  quantity, // How many NFTs you want (max 50)
  expiration,
  {
    value: pricePerNFT * quantity // Only if ETH
  }
);

// Accept trait offer (as NFT owner)
await nft.approve(offerManagerAddress, tokenId);
await offerManager.acceptTraitOffer(offerId, tokenId);
```

### 5. Bundles

#### Create Bundle

```javascript
const bundleManager = new ethers.Contract(
  bundleManagerAddress,
  BundleABI,
  signer
);

// Approve all NFTs
for (const nft of nfts) {
  await nft.contract.approve(bundleManagerAddress, nft.tokenId);
}

// Create bundle
const bundleItems = [
  {
    nftContract: nft1Address,
    tokenId: 1,
    amount: 1, // 1 for ERC721
    tokenType: 0 // 0 = ERC721, 1 = ERC1155
  },
  {
    nftContract: nft2Address,
    tokenId: 5,
    amount: 1,
    tokenType: 0
  }
];

const tx = await bundleManager.createBundle(
  bundleItems,
  totalPrice, // Price for entire bundle
  duration
);

const receipt = await tx.wait();
const bundleId = receipt.events[0].args.bundleId;
```

#### Purchase Bundle

```javascript
// Get bundle details
const bundle = await bundleManager.getBundle(bundleId);

// Purchase
await bundleManager.purchaseBundle(bundleId, {
  value: bundle.totalPrice
});
```

### 6. Advanced Listing Manager

For complex listing types:

```javascript
const listingManager = new ethers.Contract(
  listingManagerAddress,
  ListingABI,
  signer
);

// Create auction listing
await listingManager.createAuctionListing(
  nftContract,
  tokenId,
  auctionParams // Starting bid, reserve, duration, etc.
);

// Create Dutch auction
await listingManager.createDutchAuctionListing(
  nftContract,
  tokenId,
  dutchParams // Start price, end price, duration
);

// Update listing price
await listingManager.updateListingPrice(listingId, newPrice);

// Cancel listing
await listingManager.cancelListing(listingId);

// Get listing status
const status = await listingManager.getListingStatus(listingId);
```

### 7. Collection Management

#### Create New Collection

```javascript
// ERC721 Collection
const erc721Factory = new ethers.Contract(
  addresses.erc721Factory,
  ERC721FactoryABI,
  signer
);

const tx = await erc721Factory.createCollection(
  'My NFT Collection', // name
  'MNC', // symbol
  'ipfs://metadata/', // baseURI
  1000, // maxSupply
  owner, // collection owner
  500 // royalty basis points (5%)
);

const receipt = await tx.wait();
const collectionAddress = receipt.events[0].args.collection;

// ERC1155 Collection
const erc1155Factory = new ethers.Contract(
  addresses.erc1155Factory,
  ERC1155FactoryABI,
  signer
);

await erc1155Factory.createCollection(
  'My Multi-Token Collection',
  'MMT',
  'ipfs://metadata/{id}.json',
  owner
);
```

#### Verify Collection

```javascript
const collectionVerifier = new ethers.Contract(
  addresses.collectionVerifier,
  CollectionVerifierABI,
  signer
);

// Request verification
await collectionVerifier.requestVerification(
  collectionAddress,
  {
    name: 'Collection Name',
    description: 'Collection Description',
    website: 'https://collection.com',
    twitter: '@collection'
  },
  'Additional submission data',
  { value: verificationFee }
);

// Check verification status
const status = await collectionVerifier.getVerificationStatus(
  collectionAddress
);
const isVerified = await collectionVerifier.isVerified(collectionAddress);
```

### 8. Cancel Operations

```javascript
// Cancel listing
await exchange.cancelListing(listingId);

// Cancel auction
await englishAuction.cancelAuction(auctionId);

// Cancel offer
await offerManager.cancelOffer(offerId);

// Cancel bundle
await bundleManager.cancelBundle(bundleId);
```

### 9. Batch Operations

```javascript
// Batch approve NFTs
await nft.setApprovalForAll(exchangeAddress, true);

// Batch list multiple NFTs
await exchange.batchListNFT(
  nftContract,
  [tokenId1, tokenId2, tokenId3],
  [price1, price2, price3],
  duration
);

// Batch buy NFTs
await exchange.batchBuyNFT([listingId1, listingId2], { value: totalPrice });

// Batch cancel listings
await exchange.batchCancelListing([listingId1, listingId2]);
```

### 10. Additional Exchange Functions

```javascript
// Update listing price
await exchange.updateListingPrice(listingId, newPrice);

// Extend listing duration
await exchange.extendListing(listingId, additionalDuration);

// Pause/Resume listing
await exchange.pauseListing(listingId);
await exchange.resumeListing(listingId);

// Get user's active listings
const userListings = await exchange.getUserListings(userAddress);

// Get listings by collection
const collectionListings = await exchange.getCollectionListings(nftContract);

// Check if NFT is listed
const isListed = await exchange.isNFTListed(nftContract, tokenId);

// Get listing by NFT
const listing = await exchange.getListingByNFT(nftContract, tokenId);
```

### 11. Auction Management Functions

```javascript
// English Auction Functions
const englishAuction = new ethers.Contract(
  englishAuctionAddress,
  AuctionABI,
  signer
);

// Get auction details
const auction = await englishAuction.getAuction(auctionId);

// Get current highest bid
const highestBid = await englishAuction.getHighestBid(auctionId);

// Get bid history
const bidHistory = await englishAuction.getBidHistory(auctionId);

// Withdraw bid (for non-winners)
await englishAuction.withdrawBid(auctionId);

// Finalize auction (after end time)
await englishAuction.finalizeAuction(auctionId);

// Check if can bid
const canBid = await englishAuction.canBid(auctionId, bidAmount);

// Get time remaining
const timeLeft = await englishAuction.getTimeRemaining(auctionId);

// Dutch Auction Functions
const dutchAuction = new ethers.Contract(
  dutchAuctionAddress,
  DutchAuctionABI,
  signer
);

// Get current price at any time
const currentPrice = await dutchAuction.getCurrentPrice(auctionId);

// Get price at specific timestamp
const priceAtTime = await dutchAuction.getPriceAt(auctionId, timestamp);

// Calculate price decay
const priceDecay = await dutchAuction.calculatePriceDecay(auctionId);

// Check if auction is active
const isActive = await dutchAuction.isAuctionActive(auctionId);
```

### 12. Offer Management Functions

```javascript
// Get offer details
const offer = await offerManager.getOffer(offerId);

// Get all offers for an NFT
const nftOffers = await offerManager.getNFTOffers(nftContract, tokenId);

// Get user's active offers
const userOffers = await offerManager.getUserOffers(userAddress);

// Counter offer (seller proposes new price)
await offerManager.counterOffer(offerId, newPrice);

// Extend offer expiration
await offerManager.extendOffer(offerId, additionalDuration);

// Get offer history for NFT
const offerHistory = await offerManager.getOfferHistory(nftContract, tokenId);

// Check if offer is valid
const isValid = await offerManager.isOfferValid(offerId);

// Batch accept offers
await offerManager.batchAcceptOffers([offerId1, offerId2]);
```

### 13. Bundle Management Functions

```javascript
// Get bundle details
const bundle = await bundleManager.getBundle(bundleId);

// Get items in bundle
const items = await bundleManager.getBundleItems(bundleId);

// Update bundle price
await bundleManager.updateBundlePrice(bundleId, newPrice);

// Add item to bundle
await bundleManager.addItemToBundle(bundleId, nftContract, tokenId, amount);

// Remove item from bundle
await bundleManager.removeItemFromBundle(bundleId, nftContract, tokenId);

// Get user's active bundles
const userBundles = await bundleManager.getUserBundles(userAddress);

// Check if bundle is valid
const isValid = await bundleManager.isBundleValid(bundleId);
```

### 14. Collection Functions

```javascript
// Collection management
const collection = new ethers.Contract(
  collectionAddress,
  CollectionABI,
  signer
);

// Mint NFT (if authorized)
await collection.mint(recipientAddress, tokenId, metadata);

// Batch mint
await collection.batchMint(recipients, tokenIds, metadataArray);

// Set base URI
await collection.setBaseURI('ipfs://new-base-uri/');

// Set token URI
await collection.setTokenURI(tokenId, 'ipfs://token-metadata.json');

// Pause/Unpause minting
await collection.pauseMinting();
await collection.unpauseMinting();

// Get collection info
const name = await collection.name();
const symbol = await collection.symbol();
const maxSupply = await collection.maxSupply();
const totalSupply = await collection.totalSupply();

// Check mint eligibility
const canMint = await collection.canMint(userAddress);

// Get royalty info
const [royaltyRecipient, royaltyAmount] = await collection.royaltyInfo(
  tokenId,
  salePrice
);
```

### 15. Registry & Hub Query Functions

```javascript
// Hub queries
const userHub = new ethers.Contract(userHubAddress, UserHubABI, provider);

// Get contract for token standard (auto-detect)
const exchange = await userHub.getExchangeFor(nftContract);

// Get fee registry for calculations
const feeRegistry = await userHub.getFeeRegistry();

// Get factory for collection type
const factory = await userHub.getFactoryFor('ERC721');
const erc1155Factory = await userHub.getFactoryFor('ERC1155');

// Get auction contract for auction type
const englishAuction = await userHub.getAuctionFor(0); // 0 = ENGLISH
const dutchAuction = await userHub.getAuctionFor(1); // 1 = DUTCH

// Verify collection is valid
const isValid = await userHub.verifyCollection(collectionAddress);

// Check if system is paused
const isPaused = await userHub.isPaused();

// Get system health status
const { isHealthy, activeContracts, timestamp } =
  await userHub.getSystemStatus();
```

### 16. Analytics & History Functions

```javascript
const historyTracker = new ethers.Contract(
  historyTrackerAddress,
  ListingHistoryTrackerABI,
  provider
);

// ============================================================================
// NFT TRANSACTION HISTORY
// ============================================================================

// Get complete transaction history for an NFT
const nftHistory = await historyTracker.getNFTHistory(
  nftContract,
  tokenId,
  limit // max records to return (0 = all)
);
/*
Returns: TransactionRecord[] {
  listingId: bytes32,
  seller: address,
  buyer: address,
  price: uint256,
  timestamp: uint256,
  txType: enum (LISTING_CREATED, SALE_COMPLETED, etc.),
  listingType: uint8,
  isActive: bool
}
*/

// Get NFT history metadata
const nftMeta = await historyTracker.nftHistoryMeta(nftContract, tokenId);
/*
Returns: {
  totalTransactions: number of all transactions
  totalVolume: total trading volume for this NFT
  lastSalePrice: price of last sale
  lastSaleTime: timestamp of last sale
  currentOwner: current owner address
}
*/

// ============================================================================
// COLLECTION STATISTICS
// ============================================================================

// Get comprehensive collection stats
const collectionStats = await historyTracker.collectionStats(collection);
/*
Returns: CollectionStats {
  totalListings: total listings created
  totalSales: completed sales count
  totalVolume: total trading volume (ETH/WETH)
  floorPrice: current floor price ✅
  averagePrice: average sale price ✅
  highestSale: highest sale ever
  activeListings: current active listings
  lastUpdated: last update timestamp
}
*/

// Get collection price history (for charts)
const priceHistory = await historyTracker.getCollectionPriceHistory(
  collection,
  limit // max price points (0 = all, max 1000)
);
/*
Returns: PricePoint[] {
  price: sale price
  timestamp: when it happened
  volume: volume at this price
  source: transaction type
}
// Use this to build price charts!
*/

// ============================================================================
// USER STATISTICS
// ============================================================================

// Get user trading statistics
const userStats = await historyTracker.userStats(userAddress);
/*
Returns: UserStats {
  totalListings: listings created by user
  totalSales: successful sales
  totalPurchases: NFTs purchased
  volumeSold: total ETH earned
  volumeBought: total ETH spent
  averageSalePrice: avg price when selling
  averagePurchasePrice: avg price when buying
  firstActivity: first transaction timestamp
  lastActivity: most recent activity
}
*/

// ============================================================================
// GLOBAL MARKETPLACE METRICS
// ============================================================================

// Get global marketplace statistics
const globalStats = await historyTracker.globalStats();
/*
Returns: MarketplaceStats {
  totalListings: all listings ever created
  totalSales: all completed sales
  totalVolume: total trading volume (all time)
  totalUsers: unique users count
  totalCollections: collections with activity
  averageSalePrice: global average price
  dailyActiveUsers: active users today
  lastUpdated: last stats update
}
*/

// Get daily trading volume
const today = Math.floor(Date.now() / 1000 / 86400); // days since epoch
const dailyVolume = await historyTracker.dailyVolumes(today);
/*
Returns: DailyVolume {
  volume: total volume today
  transactions: transaction count today
  uniqueUsers: unique users today
  averagePrice: avg price today
}
*/

// Get yesterday's volume
const yesterday = today - 1;
const yesterdayVolume = await historyTracker.dailyVolumes(yesterday);

// ============================================================================
// REAL-TIME ANALYTICS EXAMPLES
// ============================================================================

// Calculate floor price for display
function displayFloorPrice(collectionStats) {
  if (collectionStats.floorPrice === 0n) {
    return 'No active listings';
  }
  return `${ethers.formatEther(collectionStats.floorPrice)} ETH`;
}

// Calculate 24h volume change
async function calculate24hVolumeChange(historyTracker) {
  const today = Math.floor(Date.now() / 1000 / 86400);
  const yesterday = today - 1;

  const todayVol = await historyTracker.dailyVolumes(today);
  const yesterdayVol = await historyTracker.dailyVolumes(yesterday);

  const change =
    ((todayVol.volume - yesterdayVol.volume) * 100n) / yesterdayVol.volume;
  return Number(change);
}

// Get trending collections (manual implementation)
async function getTrendingCollections(historyTracker, collections) {
  const today = Math.floor(Date.now() / 1000 / 86400);
  const trending = [];

  for (const collection of collections) {
    const stats = await historyTracker.collectionStats(collection);
    const dailyVol = await historyTracker.dailyVolumes(today);

    trending.push({
      collection,
      volume24h: dailyVol.volume,
      totalVolume: stats.totalVolume,
      floorPrice: stats.floorPrice,
      averagePrice: stats.averagePrice,
      sales24h: dailyVol.transactions
    });
  }

  // Sort by 24h volume
  return trending.sort((a, b) => Number(b.volume24h - a.volume24h));
}

// Build price chart data
async function buildPriceChart(historyTracker, collection, days = 30) {
  const priceHistory = await historyTracker.getCollectionPriceHistory(
    collection,
    0 // get all points
  );

  const cutoffTime = Date.now() / 1000 - days * 86400;

  return priceHistory
    .filter((point) => point.timestamp >= cutoffTime)
    .map((point) => ({
      date: new Date(Number(point.timestamp) * 1000),
      price: Number(ethers.formatEther(point.price)),
      volume: Number(ethers.formatEther(point.volume))
    }));
}

// Calculate user profit/loss
function calculateUserProfitLoss(userStats) {
  const profit = userStats.volumeSold - userStats.volumeBought;
  const profitPercent = (profit * 100n) / (userStats.volumeBought || 1n); // avoid div by 0

  return {
    profit: ethers.formatEther(profit),
    profitPercent: Number(profitPercent),
    totalTraded: ethers.formatEther(
      userStats.volumeSold + userStats.volumeBought
    )
  };
}
```

### 17. Utility & Helper Functions

```javascript
// Generate listing ID
function generateListingId(nftContract, tokenId, seller, timestamp) {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['address', 'uint256', 'address', 'uint256'],
      [nftContract, tokenId, seller, timestamp]
    )
  );
}

// Check NFT ownership
async function checkOwnership(nftContract, tokenId, address) {
  const nft = new ethers.Contract(nftContract, ERC721ABI, provider);
  return (await nft.ownerOf(tokenId)) === address;
}

// Check approval status
async function checkApproval(nftContract, tokenId, spender) {
  const nft = new ethers.Contract(nftContract, ERC721ABI, provider);
  const approved = await nft.getApproved(tokenId);
  const approvedForAll = await nft.isApprovedForAll(owner, spender);
  return approved === spender || approvedForAll;
}

// Format price for display
function formatPrice(priceWei) {
  return ethers.formatEther(priceWei);
}

// Parse price from input
function parsePrice(priceString) {
  return ethers.parseEther(priceString);
}

// Calculate fee amount
function calculateFee(price, feeBasisPoints) {
  return (price * BigInt(feeBasisPoints)) / BigInt(10000);
}

// Validate ethereum address
function isValidAddress(address) {
  return ethers.isAddress(address);
}

// Get block timestamp
async function getCurrentTimestamp() {
  const block = await provider.getBlock('latest');
  return block.timestamp;
}
```

## 📊 Reading Data

### Get Listing Details

```javascript
// Get listing info
const listing = await exchange.getListing(listingId);
/*
Returns:
{
  seller: address,
  contractAddress: address,
  tokenId: uint256,
  price: uint256,
  expirationTime: uint256,
  isActive: bool
}
*/
```

### Calculate Fees

```javascript
// Get complete fee breakdown
const fees = await hub.calculateFees(nftContract, tokenId, salePrice);
/*
Returns:
{
  platformFee: uint256,
  royaltyAmount: uint256,
  royaltyRecipient: address,
  sellerProceeds: uint256,
  totalPrice: uint256
}
*/
```

### Verify Collection

```javascript
// Check if collection is verified
const { isValid, tokenType } = await hub.verifyCollection(collectionAddress);
// tokenType: "ERC721" or "ERC1155"
```

## 🔧 Advanced Features

### Fee Management

#### Basic Fee Management

```javascript
const feeManager = new ethers.Contract(
  addresses.feeManager,
  FeeManagerABI,
  signer
);

// Get current fee rates
const platformFee = await feeManager.getPlatformFee(); // in basis points
const minPrice = await feeManager.getMinimumPrice();

// Calculate fees for a sale
const fees = await feeManager.calculateFees(salePrice);

// Admin functions (only for marketplace admin)
await feeManager.updatePlatformFee(250); // 2.5%
await feeManager.updateMinimumPrice(ethers.parseEther('0.001'));
await feeManager.setFeeRecipient(newRecipient);
```

#### Advanced Fee Features (Volume-Based Tiers & VIP)

**⚠️ Note:** AdvancedFeeManager is NOT directly accessible via UserHub. Query through FeeRegistry:

```javascript
// Get FeeRegistry from UserHub
const feeRegistryAddr = await userHub.getFeeRegistry();
const feeRegistry = new ethers.Contract(
  feeRegistryAddr,
  FeeRegistryABI,
  provider
);

// Get AdvancedFeeManager address from FeeRegistry
// (Implementation-specific - check your FeeRegistry contract)
const advancedFeeManagerAddr = await feeRegistry.advancedFeeManager();
const advancedFeeManager = new ethers.Contract(
  advancedFeeManagerAddr,
  AdvancedFeeManagerABI,
  provider
);

// Get user's fee tier and volume
const feeTier = await advancedFeeManager.userFeeTiers(userAddress);
const volumeData = await advancedFeeManager.userVolumeData(userAddress);

console.log('User Fee Tier:', feeTier.tierId);
console.log('Discount:', feeTier.discountBps / 100, '%');
console.log('Total Volume:', ethers.formatEther(volumeData.totalVolume), 'ETH');
console.log('Total Trades:', volumeData.tradeCount.toString());

// Calculate actual fees for a transaction
const [finalFee, appliedDiscount] = await advancedFeeManager.calculateFees(
  userAddress, // trader address
  collectionAddress, // NFT collection
  salePrice, // sale price in wei
  false // false = taker fee, true = maker fee
);

console.log('Final Fee:', ethers.formatEther(finalFee), 'ETH');
console.log('Discount Applied:', appliedDiscount / 100, '%');

// Check VIP status
const vipStatus = await advancedFeeManager.vipStatus(userAddress);
if (vipStatus.isVIP && Date.now() / 1000 < vipStatus.vipExpiryTimestamp) {
  console.log('VIP Tier:', vipStatus.vipTier);
  console.log('VIP Discount:', vipStatus.vipDiscountBps / 100, '%');
}

// Check tier upgrade eligibility
const [canUpgrade, nextTierId, volumeNeeded] =
  await advancedFeeManager.checkTierUpgradeEligibility(userAddress);

if (canUpgrade) {
  console.log('✅ User can upgrade to tier', nextTierId);
} else if (volumeNeeded > 0) {
  console.log(
    'Need',
    ethers.formatEther(volumeNeeded),
    'ETH more volume to upgrade'
  );
}

// Get collection-specific fee override
const collectionOverride = await advancedFeeManager.collectionFeeOverrides(
  collectionAddress
);

if (collectionOverride.hasOverride) {
  console.log(
    'Collection Maker Fee:',
    collectionOverride.makerFeeOverride / 100,
    '%'
  );
  console.log(
    'Collection Taker Fee:',
    collectionOverride.takerFeeOverride / 100,
    '%'
  );
  console.log(
    'Collection Discount:',
    collectionOverride.discountBps / 100,
    '%'
  );
  console.log('Is Verified:', collectionOverride.isVerified);
}

// Get total marketplace volume
const totalVolume = await advancedFeeManager.totalMarketplaceVolume();
console.log(
  'Total Marketplace Volume:',
  ethers.formatEther(totalVolume),
  'ETH'
);
```

**Fee Tier System:**

- **Bronze** (0+ ETH): 0% discount
- **Silver** (10+ ETH): 0.5% discount
- **Gold** (50+ ETH): 1% discount
- **Platinum** (100+ ETH): 2% discount
- **Diamond** (500+ ETH): 3% discount

**VIP Benefits:**

- Additional 1-5% discount on top of tier discount
- Custom fee rates for specific collections
- Priority support
- Time-limited (renewable)

### Royalty System

```javascript
const royaltyManager = new ethers.Contract(
  addresses.royaltyManager,
  RoyaltyManagerABI,
  signer
);

// Get royalty info (EIP-2981)
const [recipient, amount] = await royaltyManager.royaltyInfo(
  tokenId,
  salePrice
);

// Set custom royalty (collection owner only)
await royaltyManager.setTokenRoyalty(
  tokenId,
  royaltyRecipient,
  500 // 5% in basis points
);

// Set default royalty for collection
await royaltyManager.setDefaultRoyalty(royaltyRecipient, 250); // 2.5%

// Delete royalty
await royaltyManager.deleteTokenRoyalty(tokenId);
```

### Access Control

```javascript
const accessControl = new ethers.Contract(
  addresses.accessControl,
  AccessControlABI,
  signer
);

// Check roles
const isAdmin = await accessControl.hasRole(ADMIN_ROLE, userAddress);
const isOperator = await accessControl.hasRole(OPERATOR_ROLE, userAddress);

// Role management (admin only)
await accessControl.grantRole(OPERATOR_ROLE, newOperator);
await accessControl.revokeRole(OPERATOR_ROLE, operator);

// Get role members
const adminCount = await accessControl.getRoleMemberCount(ADMIN_ROLE);
const admin = await accessControl.getRoleMember(ADMIN_ROLE, 0);
```

### Timelock Operations

```javascript
const timelock = new ethers.Contract(addresses.timelock, TimelockABI, signer);

// Schedule a transaction (admin only)
const delay = 48 * 60 * 60; // 48 hours
await timelock.schedule(
  target, // Contract address
  value, // ETH value
  data, // Function calldata
  predecessor, // Previous tx hash (0x0 if none)
  salt, // Unique salt
  delay
);

// Execute after timelock
await timelock.execute(target, value, data, predecessor, salt);

// Cancel scheduled transaction
await timelock.cancel(operationId);

// Check operation status
const isReady = await timelock.isOperationReady(operationId);
const isPending = await timelock.isOperationPending(operationId);
```

### Listing Validation

```javascript
const validator = new ethers.Contract(
  addresses.listingValidator,
  ValidatorABI,
  signer
);

// Validate listing parameters
const isValid = await validator.validateListing(
  nftContract,
  tokenId,
  price,
  duration
);

// Validate auction parameters
const isValidAuction = await validator.validateAuction(
  nftContract,
  tokenId,
  startingPrice,
  reservePrice,
  duration
);

// Get validation errors
const errors = await validator.getValidationErrors(listingParams);
```

### Collection Verification

```javascript
const verifier = new ethers.Contract(
  addresses.collectionVerifier,
  VerifierABI,
  signer
);

// Submit collection for verification
await verifier.submitForVerification(collectionAddress, metadata, {
  value: verificationFee
});

// Check verification status
const status = await verifier.getVerificationStatus(collectionAddress);
// Returns: UNVERIFIED, PENDING, VERIFIED, REJECTED

// Get verified collections
const verifiedCollections = await verifier.getVerifiedCollections();

// Batch verify collections (admin only)
await verifier.batchVerifyCollections([collection1, collection2]);
```

### History & Analytics

```javascript
// Get HistoryTracker from UserHub
const historyTrackerAddr = await userHub.getHistoryTracker();
const historyTracker = new ethers.Contract(
  historyTrackerAddr,
  HistoryABI,
  provider
);

// Get user trading history
const userHistory = await historyTracker.getUserHistory(userAddress);
/*
Returns array of:
{
  listingId,
  action, // LISTED, SOLD, CANCELLED
  price,
  timestamp,
  nftContract,
  tokenId
}
*/

// Get collection statistics
const stats = await historyTracker.getCollectionStats(collectionAddress);
/*
Returns:
{
  totalVolume,
  totalSales,
  averagePrice,
  floorPrice,
  uniqueOwners
}
*/

// Get marketplace statistics
const marketStats = await historyTracker.getMarketplaceStats();
/*
Returns:
{
  totalVolume,
  totalTransactions,
  activeListings,
  uniqueUsers
}
*/

// Get price history for NFT
const priceHistory = await historyTracker.getNFTPriceHistory(
  nftContract,
  tokenId
);
```

## 🔔 Events

### Complete Events Reference

#### Exchange Events (ERC721/ERC1155)

```javascript
// NFT Listed for sale
exchange.on(
  'NFTListed',
  (
    listingId, // bytes32
    contractAddress, // address
    tokenId, // uint256
    seller, // address
    price, // uint256
    amount, // uint256 (1 for ERC721, multiple for ERC1155)
    paymentToken, // address
    expirationTime // uint256
  ) => {
    console.log('NFT Listed:', { listingId, seller, price });
  }
);

// NFT Sold
exchange.on(
  'NFTSold',
  (
    listingId, // bytes32
    buyer, // address
    soldPrice, // uint256
    platformFee, // uint256
    royaltyAmount // uint256
  ) => {
    console.log('NFT Sold:', { listingId, buyer, soldPrice });
  }
);

// Listing Cancelled
exchange.on(
  'ListingCancelled',
  (
    listingId, // bytes32
    seller // address
  ) => {
    console.log('Listing Cancelled:', listingId);
  }
);

// Listing Price Updated
exchange.on(
  'ListingPriceUpdated',
  (
    listingId, // bytes32
    oldPrice, // uint256
    newPrice // uint256
  ) => {
    console.log('Price Updated:', { listingId, newPrice });
  }
);

// Batch Events
exchange.on(
  'BatchListingCreated',
  (
    listingIds, // bytes32[]
    seller // address
  ) => {
    console.log('Batch Listing Created:', listingIds);
  }
);

exchange.on(
  'BatchPurchaseCompleted',
  (
    buyer, // address
    listingIds, // bytes32[]
    totalAmount // uint256
  ) => {
    console.log('Batch Purchase:', { buyer, totalAmount });
  }
);
```

#### Auction Events

```javascript
// English Auction Events
englishAuction.on(
  'AuctionCreated',
  (
    auctionId, // bytes32
    seller, // address
    nftContract, // address
    tokenId, // uint256
    startingPrice, // uint256
    reservePrice, // uint256
    startTime, // uint256
    endTime // uint256
  ) => {
    console.log('English Auction Created:', auctionId);
  }
);

englishAuction.on(
  'BidPlaced',
  (
    auctionId, // bytes32
    bidder, // address
    bidAmount, // uint256
    previousBid, // uint256
    previousBidder // address
  ) => {
    console.log('New Bid:', { auctionId, bidder, bidAmount });
  }
);

englishAuction.on(
  'AuctionFinalized',
  (
    auctionId, // bytes32
    winner, // address
    winningBid, // uint256
    platformFee, // uint256
    royaltyAmount // uint256
  ) => {
    console.log('Auction Ended:', { winner, winningBid });
  }
);

englishAuction.on(
  'AuctionCancelled',
  (
    auctionId, // bytes32
    seller // address
  ) => {
    console.log('Auction Cancelled:', auctionId);
  }
);

englishAuction.on(
  'BidWithdrawn',
  (
    auctionId, // bytes32
    bidder, // address
    amount // uint256
  ) => {
    console.log('Bid Withdrawn:', { bidder, amount });
  }
);

// Dutch Auction Events
dutchAuction.on(
  'DutchAuctionCreated',
  (
    auctionId, // bytes32
    seller, // address
    nftContract, // address
    tokenId, // uint256
    startingPrice, // uint256
    endingPrice, // uint256
    duration // uint256
  ) => {
    console.log('Dutch Auction Created:', auctionId);
  }
);

dutchAuction.on(
  'DutchAuctionPurchased',
  (
    auctionId, // bytes32
    buyer, // address
    purchasePrice, // uint256
    platformFee, // uint256
    royaltyAmount // uint256
  ) => {
    console.log('Dutch Auction Purchased:', { buyer, purchasePrice });
  }
);
```

#### Offer Events

```javascript
// NFT Offer Events
offerManager.on(
  'NFTOfferCreated',
  (
    offerId, // bytes32
    offerer, // address
    collection, // address
    tokenId, // uint256
    offerAmount, // uint256
    paymentToken, // address
    expirationTime // uint256
  ) => {
    console.log('NFT Offer Created:', { offerId, offerAmount });
  }
);

offerManager.on(
  'NFTOfferAccepted',
  (
    offerId, // bytes32
    seller, // address
    offerer, // address
    collection, // address
    tokenId, // uint256
    offerAmount // uint256
  ) => {
    console.log('Offer Accepted:', { offerId, seller });
  }
);

offerManager.on(
  'NFTOfferCancelled',
  (
    offerId, // bytes32
    offerer // address
  ) => {
    console.log('Offer Cancelled:', offerId);
  }
);

offerManager.on(
  'NFTOfferRejected',
  (
    offerId, // bytes32
    seller // address
  ) => {
    console.log('Offer Rejected:', offerId);
  }
);

// Collection Offer Events
offerManager.on(
  'CollectionOfferCreated',
  (
    offerId, // bytes32
    offerer, // address
    collection, // address
    pricePerNFT, // uint256
    quantity, // uint256
    paymentToken, // address
    expirationTime // uint256
  ) => {
    console.log('Collection Offer Created:', { collection, pricePerNFT });
  }
);

offerManager.on(
  'CollectionOfferFulfilled',
  (
    offerId, // bytes32
    seller, // address
    tokenIds, // uint256[]
    totalAmount // uint256
  ) => {
    console.log('Collection Offer Fulfilled:', { tokenIds });
  }
);
```

#### Bundle Events

```javascript
bundleManager.on(
  'BundleCreated',
  (
    bundleId, // bytes32
    creator, // address
    items, // BundleItem[]
    totalPrice, // uint256
    expirationTime // uint256
  ) => {
    console.log('Bundle Created:', { bundleId, totalPrice });
  }
);

bundleManager.on(
  'BundlePurchased',
  (
    bundleId, // bytes32
    buyer, // address
    totalPrice, // uint256
    platformFee, // uint256
    royaltyAmount // uint256
  ) => {
    console.log('Bundle Purchased:', { bundleId, buyer });
  }
);

bundleManager.on(
  'BundleCancelled',
  (
    bundleId, // bytes32
    creator // address
  ) => {
    console.log('Bundle Cancelled:', bundleId);
  }
);

bundleManager.on(
  'BundleUpdated',
  (
    bundleId, // bytes32
    newPrice, // uint256
    newExpiration // uint256
  ) => {
    console.log('Bundle Updated:', { bundleId, newPrice });
  }
);
```

#### Collection Factory Events

```javascript
// ERC721 Factory Events
erc721Factory.on(
  'CollectionCreated',
  (
    collection, // address
    creator, // address
    name, // string
    symbol, // string
    maxSupply, // uint256
    royaltyBPS // uint256
  ) => {
    console.log('ERC721 Collection Created:', collection);
  }
);

// ERC1155 Factory Events
erc1155Factory.on(
  'CollectionCreated',
  (
    collection, // address
    creator, // address
    name, // string
    symbol, // string
    uri // string
  ) => {
    console.log('ERC1155 Collection Created:', collection);
  }
);

// Collection Verification Events
collectionVerifier.on(
  'VerificationRequested',
  (
    collection, // address
    requester, // address
    feePaid, // uint256
    timestamp // uint256
  ) => {
    console.log('Verification Requested:', collection);
  }
);

collectionVerifier.on(
  'CollectionVerified',
  (
    collection, // address
    verifier, // address
    timestamp // uint256
  ) => {
    console.log('Collection Verified:', collection);
  }
);

collectionVerifier.on(
  'CollectionRejected',
  (
    collection, // address
    reviewer, // address
    reason, // string
    timestamp // uint256
  ) => {
    console.log('Collection Rejected:', { collection, reason });
  }
);
```

#### Fee & Royalty Events

```javascript
// Fee Manager Events
feeManager.on(
  'PlatformFeeUpdated',
  (
    oldFee, // uint256
    newFee, // uint256
    updater // address
  ) => {
    console.log('Platform Fee Updated:', newFee);
  }
);

feeManager.on(
  'FeeRecipientUpdated',
  (
    oldRecipient, // address
    newRecipient, // address
    updater // address
  ) => {
    console.log('Fee Recipient Updated:', newRecipient);
  }
);

feeManager.on(
  'MinimumPriceUpdated',
  (
    oldMinPrice, // uint256
    newMinPrice, // uint256
    updater // address
  ) => {
    console.log('Minimum Price Updated:', newMinPrice);
  }
);

// Royalty Manager Events
royaltyManager.on(
  'RoyaltySet',
  (
    tokenId, // uint256
    recipient, // address
    royaltyBPS // uint256
  ) => {
    console.log('Royalty Set:', { tokenId, royaltyBPS });
  }
);

royaltyManager.on(
  'DefaultRoyaltySet',
  (
    recipient, // address
    royaltyBPS // uint256
  ) => {
    console.log('Default Royalty Set:', royaltyBPS);
  }
);

royaltyManager.on(
  'RoyaltyDeleted',
  (
    tokenId // uint256
  ) => {
    console.log('Royalty Deleted:', tokenId);
  }
);
```

#### Access Control & Security Events

```javascript
// Access Control Events
accessControl.on(
  'RoleGranted',
  (
    role, // bytes32
    account, // address
    sender // address
  ) => {
    console.log('Role Granted:', { role, account });
  }
);

accessControl.on(
  'RoleRevoked',
  (
    role, // bytes32
    account, // address
    sender // address
  ) => {
    console.log('Role Revoked:', { role, account });
  }
);

accessControl.on(
  'RoleAdminChanged',
  (
    role, // bytes32
    previousAdminRole, // bytes32
    newAdminRole // bytes32
  ) => {
    console.log('Role Admin Changed:', { role, newAdminRole });
  }
);

// Emergency Manager Events
emergencyManager.on(
  'Paused',
  (
    account // address
  ) => {
    console.log('System Paused by:', account);
  }
);

emergencyManager.on(
  'Unpaused',
  (
    account // address
  ) => {
    console.log('System Unpaused by:', account);
  }
);

emergencyManager.on(
  'EmergencyWithdrawal',
  (
    token, // address
    recipient, // address
    amount // uint256
  ) => {
    console.log('Emergency Withdrawal:', { token, amount });
  }
);

// Timelock Events
timelock.on(
  'CallScheduled',
  (
    id, // bytes32
    index, // uint256
    target, // address
    value, // uint256
    data, // bytes
    predecessor, // bytes32
    delay // uint256
  ) => {
    console.log('Timelock Scheduled:', { id, delay });
  }
);

timelock.on(
  'CallExecuted',
  (
    id, // bytes32
    index, // uint256
    target, // address
    value, // uint256
    data // bytes
  ) => {
    console.log('Timelock Executed:', id);
  }
);

timelock.on(
  'Cancelled',
  (
    id // bytes32
  ) => {
    console.log('Timelock Cancelled:', id);
  }
);
```

#### Listing Manager Events

```javascript
listingManager.on(
  'ListingCreated',
  (
    listingId, // bytes32
    listingType, // enum (FIXED, AUCTION, DUTCH, BUNDLE, OFFER)
    seller, // address
    nftContract, // address
    tokenId // uint256
  ) => {
    console.log('Advanced Listing Created:', { listingId, listingType });
  }
);

listingManager.on(
  'ListingStatusChanged',
  (
    listingId, // bytes32
    oldStatus, // enum
    newStatus // enum (ACTIVE, SOLD, CANCELLED, EXPIRED, PAUSED)
  ) => {
    console.log('Listing Status Changed:', { listingId, newStatus });
  }
);

listingManager.on(
  'ListingPaused',
  (
    listingId, // bytes32
    reason // string
  ) => {
    console.log('Listing Paused:', { listingId, reason });
  }
);

listingManager.on(
  'ListingResumed',
  (
    listingId // bytes32
  ) => {
    console.log('Listing Resumed:', listingId);
  }
);
```

### Event Filtering & Querying

```javascript
// Filter events by specific parameters
const filter = exchange.filters.NFTListed(
  null, // any listingId
  nftContract, // specific NFT contract
  tokenId, // specific tokenId
  userAddress, // specific seller
  null, // any price
  null, // any amount
  null, // any payment token
  null // any expiration
);

// Query historical events
const events = await exchange.queryFilter(filter, fromBlock, toBlock);

// Listen for future events
exchange.on(filter, (event) => {
  console.log('Filtered event:', event);
});

// Remove listeners
exchange.removeAllListeners('NFTListed');
```

### Event Subscription Best Practices

```javascript
// Create a centralized event manager
class EventManager {
  private listeners: Map<string, any> = new Map();

  subscribeToExchange(exchange: ethers.Contract) {
    const listingListener = exchange.on("NFTListed", this.handleListing);
    const saleListener = exchange.on("NFTSold", this.handleSale);

    this.listeners.set("listing", listingListener);
    this.listeners.set("sale", saleListener);
  }

  private handleListing = (listingId: string, ...args: any[]) => {
    // Handle listing event
    this.updateUI({ type: "listing", listingId, data: args });
  };

  private handleSale = (listingId: string, buyer: string, price: bigint) => {
    // Handle sale event
    this.updateUI({ type: "sale", listingId, buyer, price });
  };

  unsubscribeAll() {
    this.listeners.forEach(listener => listener.removeAllListeners());
    this.listeners.clear();
  }
}
```

## ❌ Error Handling

### Complete Error Reference

#### Exchange Errors (ERC721/ERC1155)

```solidity
// Configuration Errors
NFTExchange__InvalidMarketplaceWallet()
NFTExchange__InvalidAccessControl()
NFTExchange__InvalidFeeManager()
NFTExchange__ZeroAddress()

// Listing Errors
NFTExchange__PriceMustBeGreaterThanZero()
NFTExchange__DurationMustBeGreaterThanZero()
NFTExchange__InvalidListingDuration()
NFTExchange__ListingDoesNotExist()
NFTExchange__ListingNotActive()
NFTExchange__ListingExpired()
NFTExchange__ListingAlreadyExists()

// Ownership & Permission Errors
NFTExchange__NotTheOwner()
NFTExchange__NotTheSeller()
NFTExchange__MarketplaceNotApproved()
NFTExchange__CallerNotApproved()
NFTExchange__UnauthorizedCaller()

// Transaction Errors
NFTExchange__InsufficientPayment()
NFTExchange__CannotBuyOwnNFT()
NFTExchange__TransferFailed()
NFTExchange__TransferToSellerFailed()
NFTExchange__PaymentFailed()
NFTExchange__RefundFailed()

// Validation Errors
NFTExchange__ArrayLengthMismatch()
NFTExchange__InvalidAmount()
NFTExchange__InvalidTokenId()
NFTExchange__InvalidNFTContract()
NFTExchange__InvalidPaymentToken()
NFTExchange__BatchSizeTooLarge()
```

#### Auction Errors

```solidity
// English Auction Errors
Auction__InvalidStartingPrice()
Auction__InvalidReservePrice()
Auction__InvalidDuration()
Auction__AuctionNotActive()
Auction__AuctionEnded()
Auction__AuctionNotEnded()
Auction__BidTooLow()
Auction__CannotBidOwnAuction()
Auction__ReserveNotMet()
Auction__AlreadyFinalized()
Auction__NoBidsPlaced()
Auction__BidderNotFound()
Auction__WithdrawalFailed()
Auction__NotTheHighestBidder()
Auction__CannotCancelWithBids()

// Dutch Auction Errors
DutchAuction__InvalidPriceRange()
DutchAuction__AuctionNotStarted()
DutchAuction__InvalidStartEndPrice()
DutchAuction__PriceNotDecreasing()
DutchAuction__InsufficientPayment()
DutchAuction__AuctionExpired()
```

#### Offer Errors

```solidity
// NFT Offer Errors
OfferManager__InvalidOffer()
OfferManager__OfferExpired()
OfferManager__OfferNotActive()
OfferManager__NotOfferCreator()
OfferManager__NotNFTOwner()
OfferManager__InvalidOfferAmount()
OfferManager__OfferAlreadyExists()
OfferManager__InsufficientBalance()
OfferManager__InvalidDuration()
OfferManager__TokenNotApproved()

// Collection Offer Errors
OfferManager__InvalidCollectionOffer()
OfferManager__InvalidQuantity()
OfferManager__CollectionOfferNotActive()
OfferManager__ExceedsMaxQuantity()
OfferManager__InsufficientNFTs()
```

#### Bundle Errors

```solidity
BundleManager__InvalidBundle()
BundleManager__BundleNotActive()
BundleManager__InsufficientPayment()
BundleManager__InvalidBundleSize()
BundleManager__BundleExpired()
BundleManager__NotBundleCreator()
BundleManager__InvalidBundleItems()
BundleManager__DuplicateItems()
BundleManager__ItemNotApproved()
BundleManager__InvalidTokenType()
```

#### Collection Errors

```solidity
// Factory Errors
CollectionFactory__InvalidParameters()
CollectionFactory__DeploymentFailed()
CollectionFactory__InvalidMaxSupply()
CollectionFactory__InvalidRoyaltyBPS()
CollectionFactory__ZeroAddress()

// Collection Errors
Collection__MaxSupplyExceeded()
Collection__InvalidTokenId()
Collection__TokenAlreadyMinted()
Collection__NotOwner()
Collection__InvalidMinter()
Collection__MintingPaused()
Collection__InvalidURI()

// Verification Errors
CollectionVerifier__NotVerified()
CollectionVerifier__AlreadyVerified()
CollectionVerifier__VerificationPending()
CollectionVerifier__InsufficientFee()
CollectionVerifier__InvalidSubmission()
CollectionVerifier__NotReviewer()
```

#### Fee & Royalty Errors

```solidity
// Fee Errors
FeeManager__InvalidFeePercentage()
FeeManager__FeeTooHigh()
FeeManager__InvalidFeeRecipient()
FeeManager__ZeroAddress()
FeeManager__InvalidMinimumPrice()

// Royalty Errors
RoyaltyManager__InvalidRoyaltyBPS()
RoyaltyManager__RoyaltyTooHigh()
RoyaltyManager__InvalidRecipient()
RoyaltyManager__NotCollectionOwner()
```

#### Access Control & Security Errors

```solidity
// Access Control Errors
AccessControl__Unauthorized()
AccessControl__RoleNotGranted()
AccessControl__CannotRenounceRole()
AccessControl__InvalidRole()

// Emergency Errors
Emergency__AlreadyPaused()
Emergency__NotPaused()
Emergency__NotEmergencyRole()
Emergency__WithdrawalFailed()

// Timelock Errors
Timelock__InsufficientDelay()
Timelock__NotReady()
Timelock__AlreadyScheduled()
Timelock__NotScheduled()
Timelock__InvalidOperation()
```

#### Validation Errors

```solidity
// Listing Validator Errors
Validator__InvalidPrice()
Validator__InvalidDuration()
Validator__InvalidNFTContract()
Validator__InvalidTokenId()
Validator__PriceTooLow()
Validator__DurationTooShort()
Validator__DurationTooLong()

// Marketplace Validator Errors
MarketplaceValidator__InvalidSignature()
MarketplaceValidator__ExpiredSignature()
MarketplaceValidator__InvalidNonce()
MarketplaceValidator__UsedNonce()
```

### Error Handling Examples

```javascript
// Comprehensive error handling
async function handlePurchase(listingId: string, price: bigint) {
  try {
    const tx = await exchange.buyNFT(listingId, { value: price });
    await tx.wait();
  } catch (error: any) {
    // Parse custom errors
    const errorName = error.reason?.split('(')[0];

    switch(errorName) {
      // Payment errors
      case 'NFTExchange__InsufficientPayment':
        throw new Error('Insufficient payment. Please include platform fees.');

      // Listing errors
      case 'NFTExchange__ListingNotActive':
        throw new Error('This listing is no longer active.');
      case 'NFTExchange__ListingExpired':
        throw new Error('This listing has expired.');

      // Permission errors
      case 'NFTExchange__CannotBuyOwnNFT':
        throw new Error('You cannot buy your own NFT.');
      case 'NFTExchange__NotTheOwner':
        throw new Error('You do not own this NFT.');

      // Transaction errors
      case 'NFTExchange__TransferFailed':
        throw new Error('NFT transfer failed. Please try again.');

      default:
        throw new Error(`Transaction failed: ${error.message}`);
    }
  }
}

// Error recovery pattern
async function safeTransaction(fn: () => Promise<any>, maxRetries = 3) {
  let lastError;

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error: any) {
      lastError = error;

      // Don't retry on certain errors
      const noRetryErrors = [
        'NFTExchange__ListingNotActive',
        'NFTExchange__CannotBuyOwnNFT',
        'NFTExchange__NotTheOwner',
        'Auction__AuctionEnded'
      ];

      if (noRetryErrors.some(e => error.message.includes(e))) {
        throw error;
      }

      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
    }
  }

  throw lastError;
}
```

## 🔒 Security Considerations

### Before Trading

1. **Always check approvals**

```javascript
const isApproved = await nft.isApprovedForAll(userAddress, exchangeAddress);
if (!isApproved) {
  await nft.setApprovalForAll(exchangeAddress, true);
}
```

2. **Verify contract addresses**

```javascript
// Always verify through hub
const isValidExchange = await hub.isRegisteredExchange(exchangeAddress);
```

3. **Check listing status**

```javascript
const listing = await exchange.getListing(listingId);
if (!listing.isActive || listing.expirationTime < Date.now() / 1000) {
  // Listing expired or sold
}
```

## 🛠️ Utility Functions

### Format Prices

```javascript
// Wei to ETH
const ethPrice = ethers.utils.formatEther(weiPrice);

// ETH to Wei
const weiPrice = ethers.utils.parseEther('1.5');
```

### Generate Listing ID

```javascript
// Listing ID is deterministic
const listingId = ethers.utils.keccak256(
  ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'address', 'uint256'],
    [nftContract, tokenId, seller, timestamp]
  )
);
```

### Check Token Standard

```javascript
// Check if ERC721 or ERC1155
const isERC721 =
  (await hub.getExchangeFor(nftContract)) == (await hub.getERC721Exchange());
const isERC1155 = !isERC721;
```

## 📈 Gas Optimization Tips

1. **Batch Operations**: Use batch functions when dealing with multiple NFTs
2. **Collection Approvals**: Use `setApprovalForAll` instead of individual approvals
3. **Fee Calculation**: Calculate fees off-chain before transactions
4. **Event Filtering**: Use indexed parameters for efficient event filtering

## 🔄 Migration from Old System

If migrating from direct exchange calls:

**Old way:**

```javascript
// Had to manage multiple exchange addresses
const erc721Exchange = '0x...';
const erc1155Exchange = '0x...';
// Manual detection of which to use
```

**New way:**

```javascript
// Just use hub
const exchange = await hub.getExchangeFor(nftContract);
// Automatic detection!
```

## 📞 Support Functions

### Emergency Controls

```javascript
// Get EmergencyManager from UserHub
const emergencyManagerAddr = await userHub.getEmergencyManager();
const emergencyManager = new ethers.Contract(
  emergencyManagerAddr,
  EmergencyManagerABI,
  signer
);

// Check if system is paused
const isPaused = await emergencyManager.paused();

// Admin: Emergency pause
await emergencyManager.emergencyPause('Security incident detected');

// Admin: Unpause system
await emergencyManager.unpause();

// Admin: Emergency withdraw stuck funds
await emergencyManager.emergencyWithdraw(tokenAddress, amount);

// Get pause history
const pauseCount = await emergencyManager.pauseCount();
const lastPauseTime = await emergencyManager.lastPauseTimestamp();
```

### NFT Status Validation (Conflict Prevention)

**⚠️ Note:** MarketplaceValidator is NOT directly accessible via UserHub. You need the deployed address:

```javascript
// MarketplaceValidator address from deployment
const MARKETPLACE_VALIDATOR = '0x...'; // From deployment output

const validator = new ethers.Contract(
  MARKETPLACE_VALIDATOR,
  ValidatorABI,
  provider
);

// Check if NFT is available for listing/auction
const [isAvailable, currentStatus] = await validator.isNFTAvailable(
  nftContract,
  tokenId,
  ownerAddress
);

console.log('Is Available:', isAvailable);
console.log('Current Status:', currentStatus);
// Status values: AVAILABLE, LISTED, AUCTIONED, SOLD, CANCELLED

// Get NFT listing/auction ID
const nftId = await validator.getNFTIdentifier(
  nftContract,
  tokenId,
  ownerAddress
);

// Check if exchange is registered
const isRegistered = await validator.registeredExchanges(exchangeAddress);

// Get all registered exchanges
const allExchanges = await validator.getAllExchanges();

// Get all registered auctions
const allAuctions = await validator.getAllAuctions();
```

**How it works:**

1. When you list an NFT, it's marked as `LISTED` in the validator
2. If you try to auction the same NFT, it will revert with `NFTNotAvailable`
3. When NFT is sold/cancelled, status is updated to `SOLD`/`CANCELLED`
4. Prevents double-listing and conflicts between Exchange and Auction

**Admin Functions:**

```javascript
// Connect as admin
const adminValidator = validator.connect(adminSigner);

// Register new exchange
await adminValidator.registerExchange(exchangeAddress, exchangeType);

// Register new auction
await adminValidator.registerAuction(auctionAddress, auctionType);

// Emergency: Reset NFT status
await adminValidator.emergencyResetNFTStatus(
  nftContract,
  tokenId,
  ownerAddress
);
```

### History Tracking

```javascript
const historyTracker = new ethers.Contract(
  historyAddress,
  HistoryABI,
  provider
);

// Get user's listing history
const userListings = await historyTracker.getUserListingHistory(userAddress);

// Get collection stats
const stats = await historyTracker.getCollectionStats(collectionAddress);
```

## 🎯 Complete Integration Example

```javascript
// 1. Setup
const hub = new ethers.Contract(MARKETPLACE_HUB, HubABI, signer);
const addresses = await hub.getAllAddresses();

// 2. List NFT
const nft = new ethers.Contract(nftAddress, ERC721ABI, signer);
const exchange = new ethers.Contract(
  addresses.erc721Exchange,
  ExchangeABI,
  signer
);

await nft.approve(addresses.erc721Exchange, tokenId);
await exchange.listNFT(nftAddress, tokenId, parseEther('1'), 86400);

// 3. Make offer
const offerManager = new ethers.Contract(
  addresses.offerManager,
  OfferABI,
  signer
);
await offerManager.createNFTOffer(
  nftAddress,
  tokenId,
  parseEther('0.8'),
  86400,
  {
    value: parseEther('0.8')
  }
);

// 4. Create bundle
const bundleManager = new ethers.Contract(
  addresses.bundleManager,
  BundleABI,
  signer
);
await bundleManager.createBundle(items, parseEther('5'), 86400);

// 5. Start auction
const auctionFactory = new ethers.Contract(
  addresses.auctionFactory,
  FactoryABI,
  signer
);
await auctionFactory.createEnglishAuction(
  nftAddress,
  tokenId,
  1,
  parseEther('0.5'),
  parseEther('1'),
  86400
);
```

## TypeScript Integration

### Type Definitions

```typescript
// types/marketplace.types.ts
export interface MarketplaceAddresses {
  erc721Exchange: string;
  erc1155Exchange: string;
  erc721Factory: string;
  erc1155Factory: string;
  englishAuction: string;
  dutchAuction: string;
  auctionFactory: string;
  feeRegistry: string;
  bundleManager: string;
  offerManager: string;
  accessControl: string;
  emergencyManager: string;
  timelock: string;
  listingValidator: string;
  collectionVerifier: string;
  historyTracker: string;
}

export enum ListingStatus {
  ACTIVE = 0,
  SOLD = 1,
  CANCELLED = 2,
  EXPIRED = 3,
  PAUSED = 4,
  PENDING = 5
}

export enum AuctionType {
  ENGLISH = 0,
  DUTCH = 1
}

export interface Listing {
  listingId: string;
  seller: string;
  nftContract: string;
  tokenId: bigint;
  amount: bigint;
  price: bigint;
  paymentToken: string;
  expirationTime: bigint;
  status: ListingStatus;
}

export interface Auction {
  auctionId: string;
  seller: string;
  nftContract: string;
  tokenId: bigint;
  startingPrice: bigint;
  reservePrice: bigint;
  currentBid: bigint;
  highestBidder: string;
  startTime: bigint;
  endTime: bigint;
  isActive: boolean;
}
```

### Service Layer

```typescript
// services/MarketplaceService.ts
export class MarketplaceService {
  private hub: ethers.Contract;
  private contracts: MarketplaceAddresses;
  private signer: ethers.Signer;

  async listNFT(params: ListingParams): Promise<string> {
    const exchange = await this.getExchange(params.nftContract);
    const tx = await exchange.listNFT(
      params.nftContract,
      params.tokenId,
      params.price,
      params.duration
    );
    const receipt = await tx.wait();
    return receipt.logs[0].args.listingId;
  }

  async createAuction(params: AuctionParams): Promise<string> {
    const factory = this.getContract('auctionFactory');
    const method =
      params.type === AuctionType.ENGLISH
        ? 'createEnglishAuction'
        : 'createDutchAuction';

    const tx = await factory[method](...Object.values(params));
    const receipt = await tx.wait();
    return receipt.logs[0].args.auctionId;
  }

  private async getExchange(nftContract: string): Promise<ethers.Contract> {
    const exchangeAddr = await this.hub.getExchangeFor(nftContract);
    return new ethers.Contract(exchangeAddr, ExchangeABI, this.signer);
  }
}
```

## Best Practices

### 1. Always Use the Hub

```typescript
// ✅ GOOD - Use hub for discovery
const exchangeAddr = await hub.getExchangeFor(nftContract);

// ❌ BAD - Hardcoding addresses
const exchange = '0x123...'; // Don't do this!
```

### 2. Handle All Errors

```typescript
async function safePurchase(listingId: string, price: bigint) {
  try {
    // Calculate total with fees via fee registry
    const feeRegistry = new ethers.Contract(
      addresses.feeRegistry,
      FeeRegistryABI,
      provider
    );
    const fees = await feeRegistry.calculateFees(nftContract, tokenId, price);

    // Check user balance
    const balance = await provider.getBalance(userAddress);
    if (balance < fees.totalPrice) {
      throw new Error('Insufficient balance');
    }

    // Execute purchase
    const tx = await exchange.buyNFT(listingId, {
      value: fees.totalPrice
    });

    return await tx.wait();
  } catch (error) {
    if (error.code === 'INSUFFICIENT_FUNDS') {
      showError('Not enough ETH in wallet');
    } else if (error.reason?.includes('ListingNotActive')) {
      showError('This NFT has already been sold');
    } else {
      showError('Transaction failed. Please try again.');
    }
    throw error;
  }
}
```

### 3. Optimize Gas Usage

```typescript
// Use batch operations when possible
await exchange.batchListNFT(nfts, prices, duration);

// Use setApprovalForAll for multiple NFTs
await nft.setApprovalForAll(exchangeAddress, true);

// Estimate gas with buffer
const gasEstimate = await tx.estimateGas();
const gasLimit = gasEstimate.mul(110).div(100); // 10% buffer
```

### 4. Cache Contract Instances

```typescript
class ContractManager {
  private cache = new Map<string, ethers.Contract>();

  getContract(address: string, abi: any): ethers.Contract {
    if (!this.cache.has(address)) {
      this.cache.set(address, new ethers.Contract(address, abi, this.signer));
    }
    return this.cache.get(address)!;
  }
}
```

### 5. Monitor Events Efficiently

```typescript
// Use filters for specific events
const filter = exchange.filters.NFTListed(
  null, // any listingId
  nftContract, // specific NFT contract
  null, // any tokenId
  userAddress // specific seller
);

// Query historical events with block range
const events = await exchange.queryFilter(filter, -10000, 'latest');
```

### 6. Validate Before Sending Transactions

```typescript
// Always validate inputs
async function validateAndList(params: ListingParams) {
  // Check ownership
  const owner = await nft.ownerOf(params.tokenId);
  if (owner !== userAddress) {
    throw new Error('You do not own this NFT');
  }

  // Check approval
  const approved = await nft.getApproved(params.tokenId);
  if (approved !== exchangeAddress) {
    await nft.approve(exchangeAddress, params.tokenId);
  }

  // Validate with contract
  const isValid = await validator.validateListing(
    params.nftContract,
    params.tokenId,
    params.price,
    params.duration
  );

  if (!isValid) {
    throw new Error('Invalid listing parameters');
  }

  // Proceed with listing
  return await exchange.listNFT(...params);
}
```

## 📚 Additional Resources

- [Contract ABIs](./abis/)
- [TypeScript Types](./types/)
- [Gas Benchmarks](./gas-benchmarks.md)
- [Security Audit](./audit/)
- [Frontend Examples](https://github.com/zunokit/marketplace-frontend)
- [Smart Contract Repository](https://github.com/zunokit/zuno-marketplace-contracts)

---

**Remember**:

- The UserHub is your single entry point for frontend operations
- AdminHub is for admin-only operations (registrations, emergency controls)
- Always calculate fees before purchases via FeeRegistry
- Handle errors gracefully
- Use batch operations when possible
- Cache contract instances for better performance
