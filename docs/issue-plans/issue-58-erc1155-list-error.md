# Issue #58: Single List Exchange Feature ERC1155 Error

## Issue Summary
**Title**: Single list `Exchange feature` ERC1155 error

**Error**: `NFTExchange__NotTheOwner()` (selector: `0x400351a8`)

**Affected Components**:
- `ERC1155NFTExchange.sol`
- `NFTValidationLib.sol`

## Root Cause Analysis

### Error Location
The error `NFTExchange__NotTheOwner()` is thrown when attempting to list an ERC1155 token.

### Key Difference: ERC721 vs ERC1155 Ownership

| Standard | Ownership Concept | Check Method |
|----------|------------------|--------------|
| ERC721 | Single owner per token | `ownerOf(tokenId) == address` |
| ERC1155 | Balance-based | `balanceOf(address, tokenId) >= amount` |

### Current Validation Logic

**ERC721 (`ERC721NFTExchange.sol:70-75`)**:
```solidity
NFTValidationLib.ValidationResult memory result = NFTValidationLib.validateERC721(
    nftContract, tokenId, msg.sender, address(this)
);

if (!result.isValid) {
    if (keccak256(bytes(result.errorMessage)) == keccak256(bytes("Not the owner"))) {
        revert NFTExchange__NotTheOwner();
    }
    // ...
}
```

**ERC1155 (`ERC1155NFTExchange.sol`)**:
The ERC1155 implementation uses `NFTValidationLib.validateERC1155()` but may handle the "Not the owner" case differently.

### Potential Root Causes

#### Cause A: Balance Check vs Ownership Check
ERC1155 doesn't have an "owner" concept. The validation might be incorrectly checking for ownership instead of sufficient balance.

#### Cause B: Amount Parameter Issue
When listing ERC1155, the `amount` parameter might not be passed correctly:
```solidity
validateERC1155(nftContract, tokenId, amount, msg.sender, address(this))
```

#### Cause C: SDK Not Passing Amount
The SDK might not be sending the correct `amount` parameter when listing ERC1155.

## Investigation Steps

### Step 1: Check NFTValidationLib.validateERC1155
```solidity
function validateERC1155(
    address nftContract,
    uint256 tokenId,
    uint256 amount,
    address owner,
    address spender
) internal view returns (ValidationResult memory)
```

Verify:
- Balance check: `balanceOf(owner, tokenId) >= amount`
- Approval check: `isApprovedForAll(owner, spender)`

### Step 2: Check SDK Listing Call
```typescript
// ExchangeModule.ts
async listNFT(params: ListNFTParams): Promise<TransactionResult> {
  // For ERC1155, amount should be passed
  if (isERC1155) {
    return this.contract.listNFT(
      nftContract,
      tokenId,
      amount,  // <-- Is this being passed correctly?
      price,
      duration
    );
  }
}
```

### Step 3: Verify Contract Function Signature
```solidity
// ERC1155NFTExchange.sol
function listNFT(
    address nftContract,
    uint256 tokenId,
    uint256 amount,     // <-- ERC1155 requires amount
    uint256 price,
    uint256 duration
) external returns (bytes32)
```

## Implementation Plan

### Phase 1: Fix Validation Logic (If Needed)
```solidity
// NFTValidationLib.sol
function validateERC1155(
    address nftContract,
    uint256 tokenId,
    uint256 amount,
    address owner,
    address spender
) internal view returns (ValidationResult memory) {
    // Check balance (not ownership)
    uint256 balance = IERC1155(nftContract).balanceOf(owner, tokenId);
    if (balance < amount) {
        return ValidationResult({
            isValid: false,
            errorMessage: "Insufficient balance"  // Not "Not the owner"
        });
    }

    // Check approval
    if (!IERC1155(nftContract).isApprovedForAll(owner, spender)) {
        return ValidationResult({
            isValid: false,
            errorMessage: "Not approved"
        });
    }

    return ValidationResult({isValid: true, errorMessage: ""});
}
```

### Phase 2: Update ERC1155NFTExchange Error Handling
```solidity
// ERC1155NFTExchange.sol - listNFT function
function listNFT(...) external returns (bytes32) {
    NFTValidationLib.ValidationResult memory result = NFTValidationLib.validateERC1155(
        nftContract, tokenId, amount, msg.sender, address(this)
    );

    if (!result.isValid) {
        // Use appropriate error based on validation message
        if (keccak256(bytes(result.errorMessage)) == keccak256(bytes("Insufficient balance"))) {
            revert NFTExchange__InsufficientBalance();
        }
        if (keccak256(bytes(result.errorMessage)) == keccak256(bytes("Not approved"))) {
            revert NFTExchange__MarketplaceNotApproved();
        }
        // Fallback for other errors
        revert NFTExchange__InvalidListingParameters();
    }
    // ...
}
```

### Phase 3: SDK Fixes
```typescript
// ExchangeModule.ts
async listNFT(params: {
  nftContract: string;
  tokenId: number;
  amount?: number;  // Optional, defaults to 1
  price: string;
  duration: number;
}): Promise<TransactionResult> {
  const tokenStandard = await this.detectTokenStandard(params.nftContract);

  if (tokenStandard === TokenStandard.ERC1155) {
    const amount = params.amount ?? 1;

    // Pre-flight validation
    const balance = await this.getERC1155Balance(
      params.nftContract,
      this.signer.address,
      params.tokenId
    );

    if (balance < amount) {
      throw new ZunoSDKError(
        ErrorCodes.INSUFFICIENT_BALANCE,
        `You only have ${balance} of this token, but tried to list ${amount}`
      );
    }

    // Proceed with listing
    return this.erc1155Exchange.listNFT(
      params.nftContract,
      params.tokenId,
      amount,
      ethers.parseEther(params.price),
      params.duration
    );
  }

  // ERC721 flow
  return this.erc721Exchange.listNFT(...);
}
```

## Files to Modify

| File | Change |
|------|--------|
| `src/libraries/NFTValidationLib.sol` | Fix ERC1155 validation to check balance not ownership |
| `src/core/exchange/ERC1155NFTExchange.sol` | Update error handling for validation failures |
| `src/errors/NFTExchangeErrors.sol` | Ensure `NFTExchange__InsufficientBalance` exists |
| `E:/zuno-marketplace-sdk/src/modules/ExchangeModule.ts` | Add pre-flight balance check |
| `test/unit/exchange/ERC1155NFTExchange.t.sol` | Add balance validation tests |

## Test Cases
```solidity
function test_ListERC1155_SuccessWithSufficientBalance() public {
    // Mint 10 tokens to seller
    mockERC1155.mint(SELLER, TOKEN_ID, 10);
    vm.prank(SELLER);
    mockERC1155.setApprovalForAll(address(exchange), true);

    vm.prank(SELLER);
    bytes32 listingId = exchange.listNFT(
        address(mockERC1155),
        TOKEN_ID,
        5,  // List 5 of 10
        1 ether,
        1 days
    );
    assertTrue(listingId != bytes32(0));
}

function test_ListERC1155_FailsWithInsufficientBalance() public {
    mockERC1155.mint(SELLER, TOKEN_ID, 2);

    vm.prank(SELLER);
    vm.expectRevert(NFTExchange__InsufficientBalance.selector);
    exchange.listNFT(
        address(mockERC1155),
        TOKEN_ID,
        5,  // Try to list 5 but only have 2
        1 ether,
        1 days
    );
}

function test_ListERC1155_FailsWithoutApproval() public {
    mockERC1155.mint(SELLER, TOKEN_ID, 10);
    // No approval set

    vm.prank(SELLER);
    vm.expectRevert(NFTExchange__MarketplaceNotApproved.selector);
    exchange.listNFT(
        address(mockERC1155),
        TOKEN_ID,
        5,
        1 ether,
        1 days
    );
}
```

## Acceptance Criteria
1. ERC1155 listing works when user has sufficient balance
2. Clear error message for insufficient balance (not "Not the owner")
3. Clear error message for missing approval
4. SDK validates balance before submitting transaction
5. All existing tests pass
6. New edge case tests added
