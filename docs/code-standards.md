# Zuno Marketplace - Code Standards and Conventions

**Document Version:** 1.0
**Last Updated:** 2026-01-07
**Solidity Version:** ^0.8.30
**Framework:** Foundry

---

## 1. Overview

This document defines the coding standards, conventions, and best practices for the Zuno Marketplace smart contract project. All contributors MUST follow these standards to ensure code consistency, security, and maintainability.

**Core Principles:**
1. **Security First:** Never compromise security for convenience
2. **Gas Efficiency:** Optimize for gas without sacrificing readability
3. **Test-Driven Development:** RED-GREEN-REFACTOR cycle is mandatory
4. **Code Quality:** Clean, readable, and well-documented code
5. **Consistency:** Follow established patterns throughout the codebase

---

## 2. Solidity Style Guidelines

### 2.1 File Organization

#### File Structure
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Imports (grouped and sorted)
import {ExternalContract1} from "path/to/Contract1.sol";
import {ExternalContract2} from "path/to/Contract2.sol";

import {InternalContract1} from "path/to/Internal1.sol";
import {InternalContract2} from "path/to/Internal2.sol";

// Contract/Interface/Library
contract ContractName {
    // 1. Error definitions
    // 2. Events
    // 3. Modifiers
    // 4. State variables
    // 5. Functions
}
```

#### Import Ordering
1. External dependencies (OpenZeppelin, etc.)
2. Internal dependencies (project contracts)
3. Use named imports: `import {Contract} from "path.sol";`

#### File Naming
- **Contracts:** PascalCase (e.g., `ERC721NFTExchange.sol`)
- **Interfaces:** PascalCase with `I` prefix (e.g., `IExchange.sol`)
- **Libraries:** PascalCase with `Lib` suffix (e.g., `PaymentDistributionLib.sol`)
- **Errors:** PascalCase with `Errors` suffix (e.g., `ExchangeErrors.sol`)
- **Events:** PascalCase with `Events` suffix (e.g., `ExchangeEvents.sol`)
- **Types:** PascalCase with `Types` suffix (e.g., `ListingTypes.sol`)

### 2.2 Code Formatting

#### Indentation and Spacing
- **Indentation:** 4 spaces (no tabs)
- **Line Length:** Max 120 characters (soft limit: 100)
- **Blank Lines:** 1 blank line between functions, 2 between sections

#### Brace Style
```solidity
function example() public {
    if (condition) {
        // Do something
    } else {
        // Do something else
    }
}
```

#### Spacing Rules
```solidity
// Good
function add(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
}

// Bad
function add(uint256 a,uint256 b)public pure returns(uint256){
    return a+b;
}
```

### 2.3 NatSpec Documentation

**Required for ALL contracts, interfaces, functions, and public state variables.**

#### Contract NatSpec
```solidity
/// @title ERC721 NFT Exchange
/// @notice Facilitates fixed-price trading of ERC721 tokens
/// @dev Implements BaseNFTExchange with ERC721-specific logic
contract ERC721NFTExchange is BaseNFTExchange {
    // ...
}
```

#### Function NatSpec
```solidity
/// @notice Creates a new listing for an ERC721 token
/// @dev Validates ownership and approval before listing
/// @param nftContract Address of the ERC721 contract
/// @param tokenId ID of the token to list
/// @param price Sale price in wei
/// @param duration Listing duration in seconds
/// @return listingId The ID of the created listing
function createListing(
    address nftContract,
    uint256 tokenId,
    uint256 price,
    uint256 duration
) external returns (bytes32 listingId) {
    // ...
}
```

#### Event NatSpec
```solidity
/// @notice Emitted when a new listing is created
/// @param listingId Unique identifier for the listing
/// @param seller Address of the seller
/// @param nftContract Address of the NFT contract
/// @param tokenId ID of the listed token
/// @param price Sale price in wei
event ListingCreated(
    bytes32 indexed listingId,
    address indexed seller,
    address indexed nftContract,
    uint256 tokenId,
    uint256 price
);
```

#### Error NatSpec
```solidity
/// @notice Emitted when the caller is not the listing owner
/// @param caller Address of the caller
/// @param owner Address of the listing owner
error ERC721NFTExchange__NotListingOwner(address caller, address owner);
```

---

## 3. Naming Conventions

### 3.1 Contract and Interface Names

**PascalCase** for contracts and interfaces:
```solidity
contract ERC721NFTExchange { }
interface IExchange { }
library PaymentDistributionLib { }
```

**Interface Prefix:** Always use `I` prefix for interfaces:
```solidity
interface IExchangeCore { }
interface ICollectionFactory { }
```

**Library Suffix:** Always use `Lib` suffix for libraries:
```solidity
library PaymentDistributionLib { }
library NFTValidationLib { }
```

### 3.2 Function Names

**camelCase** for functions:
```solidity
function createListing() public { }
function calculateFee() private view returns (uint256) { }
```

**Function Naming Patterns:**
- **Actions:** `create`, `update`, `cancel`, `execute`, `finalize`
- **Queries:** `get`, `has`, `is`, `can`, `should`
- **Callbacks:** `before`, `after`, `on`
- **Internal:** `_functionName` for internal functions

```solidity
// Good
function createListing() external { }
function getListing(bytes32 id) external view returns (Listing memory) { }
function _validateListing(Listing memory listing) internal pure { }

// Bad
function CreateListing() external { } // Wrong case
function listing_details() external view { } // Should be camelCase
function validateListing() internal { } // Should have underscore
```

### 3.3 Variable Names

**camelCase** for local and state variables:
```solidity
uint256 listingPrice;
address nftContract;
bytes32 listingId;
```

**Constants:** UPPER_SNAKE_CASE:
```solidity
uint256 constant MAX_FEE = 1000;
uint256 constant BPS_DENOMINATOR = 10000;
```

**Immutable Variables:** iCamelCase (with `i` prefix):
```solidity
address immutable iOwner;
uint256 immutable iMaxSupply;
```

**State Variables:** Prefix with visibility where helpful:
```solidity
// Internal state variables
mapping(bytes32 => Listing) internal s_listings;
uint256 internal s_takerFee;

// Public state variables
mapping(address => uint256) public balances;
```

**Storage Variable Prefix:** Use `s_` prefix for state variables to distinguish from local variables:
```solidity
contract Example {
    // State variables with s_ prefix
    uint256 private s_totalSupply;
    mapping(address => uint256) private s_balances;

    function example() public {
        uint256 totalSupply = s_totalSupply; // Clear distinction
    }
}
```

### 3.4 Event Names

**PascalCase** with descriptive names:
```solidity
event ListingCreated(bytes32 indexed listingId, address indexed seller);
event BidPlaced(bytes32 indexed auctionId, address indexed bidder, uint256 amount);
event AuctionFinalized(bytes32 indexed auctionId, address indexed winner);
```

**Event Naming Pattern:** Past tense or passive voice:
```solidity
// Good
event ListingCreated(...);
event BidPlaced(...);
event OwnershipTransferred(...);

// Bad
event createListing(...);  // Wrong case
event CreateListing(...);  // Not past tense
```

### 3.5 Error Names

**PascalCase** with double underscore separation:
```solidity
error ERC721NFTExchange__InvalidPrice(uint256 price, uint256 minPrice);
error ERC721NFTExchange__NotListingOwner(address caller, address owner);
error ERC721NFTExchange__ListingExpired(bytes32 listingId);
```

**Error Naming Pattern:** `ContractName__ErrorName`:
```solidity
// Good
error ERC721NFTExchange__ZeroAddress();
error PaymentDistributionLib__InvalidFeeAmount(uint256 amount);

// Bad
error InvalidPrice();  // Missing contract prefix
error ERC721NFTExchange_invalidPrice();  // Wrong separator
error ERC721NFTExchange_Invalid_Price();  // No spaces
```

**Error Benefits:** ~50 gas savings per revert vs require strings.

### 3.6 Modifier Names

**camelCase** with descriptive names:
```solidity
modifier onlyAdmin() { }
modifier whenNotPaused() { }
modifier validListing(bytes32 listingId) { }
```

**Modifier Naming Pattern:** Adjectives or conditions:
```solidity
// Good
modifier onlyAdmin() { }
modifier whenNotPaused() { }
modifier validListing(bytes32 listingId) { }

// Bad
modifier admin() { }  // Not descriptive
modifier notPaused() { }  // Missing 'when'
```

### 3.7 Struct and Enum Names

**PascalCase** for structs and enums:
```solidity
struct Listing { }
struct AuctionParams { }
enum ListingStatus { }

// Enum values: UPPER_SNAKE_CASE
enum ListingStatus {
    ACTIVE,
    SOLD,
    CANCELLED,
    EXPIRED
}
```

---

## 4. Code Organization Patterns

### 4.1 Contract Organization

**Order of Elements:**
1. Type declarations
2. State variables
3. Events
4. Modifiers
5. Functions

```solidity
contract ExampleContract {
    // 1. Type declarations
    enum Status { ACTIVE, INACTIVE }
    struct Data { uint256 value; }

    // 2. State variables
    uint256 private s_value;
    mapping(address => uint256) private s_balances;

    // 3. Events
    event ValueUpdated(uint256 newValue);

    // 4. Modifiers
    modifier onlyAdmin() { _; }

    // 5. Functions
    constructor() { }
    function updateValue(uint256 newValue) external onlyAdmin { }
}
```

### 4.2 Function Organization

**Order of Functions:**
1. Constructor
2. External functions (public interface)
3. Public functions (public interface)
4. Internal functions
5. Private functions

**Within Function Groups:**
1. Getters/view functions
2. State-changing functions
3. Internal helpers

### 4.3 Library Usage

**Use libraries for reusable logic:**
```solidity
import {PaymentDistributionLib} from "libraries/PaymentDistributionLib.sol";

contract Example {
    function distribute(uint256 amount) internal {
        PaymentDistributionLib.distribute(amount);
    }
}
```

**Benefits:**
- Code reuse
- Gas efficiency (via `using for` syntax)
- Better organization
- Easier testing

### 4.4 Interface Implementation

**Always implement interfaces for external contracts:**
```solidity
import {IExchangeCore} from "interfaces/IExchangeCore.sol";

contract ERC721NFTExchange is IExchangeCore {
    function createListing(...) external override returns (bytes32) {
        // Implementation
    }
}
```

**Benefits:**
- Clear contract boundaries
- Type safety
- Better documentation
- Easier testing

---

## 5. Testing Standards

### 5.1 RED-GREEN-REFACTOR Methodology

**MANDATORY for ALL code changes.**

#### 1. RED Phase: Write Failing Tests First
```solidity
// Test file: ERC721NFTExchange.t.sol

function testCreateListing_Valid() public {
    // Arrange
    address seller = address(0x1);
    uint256 price = 1 ether;

    // Act & Assert
    vm.expectRevert(); // Will fail until implemented
    exchange.createListing(nftContract, tokenId, price, duration);
}
```

**Run test to confirm it fails:**
```bash
forge test --match-test testCreateListing_Valid
```

#### 2. GREEN Phase: Implement to Pass Tests
```solidity
// Implementation file: ERC721NFTExchange.sol

function createListing(...) external returns (bytes32) {
    // Minimal implementation to pass test
    bytes32 listingId = keccak256(abi.encodePacked(msg.sender, block.timestamp));
    s_listings[listingId] = Listing({
        seller: msg.sender,
        price: price,
        // ...
    });
    return listingId;
}
```

**Run test to confirm it passes:**
```bash
forge test --match-test testCreateListing_Valid
```

#### 3. REFACTOR Phase: Improve Code
```solidity
// Refactor for better quality while keeping tests passing
function createListing(...) external nonReentrant returns (bytes32) {
    // Validation
    _validateListingPrice(price);
    _validateListingDuration(duration);
    _validateOwnership(nftContract, tokenId);

    // Create listing
    bytes32 listingId = _generateListingId(nftContract, tokenId);
    s_listings[listingId] = Listing({
        seller: msg.sender,
        price: price,
        duration: duration,
        status: ListingStatus.ACTIVE
    });

    emit ListingCreated(listingId, msg.sender, nftContract, tokenId, price);
    return listingId;
}
```

**Run all tests to confirm nothing broke:**
```bash
forge test
```

### 5.2 Test File Organization

#### Test File Structure
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ERC721NFTExchange} from "src/exchange/ERC721NFTExchange.sol";

contract ERC721NFTExchangeTest is Test {
    // 1. State variables
    ERC721NFTExchange exchange;
    address admin = address(0x1);
    address seller = address(0x2);
    address buyer = address(0x3);

    // 2. Setup function
    function setUp() public {
        vm.prank(admin);
        exchange = new ERC721NFTExchange();
        exchange.initialize(admin);
    }

    // 3. Unit tests
    function testCreateListing_Valid() public { }
    function testCreateListing_ZeroAddress() public { }
    function testCreateListing_InvalidPrice() public { }

    // 4. Integration tests
    function testFullPurchaseFlow() public { }

    // 5. Fuzz tests
    function testFuzzCreateListing_Price(uint256 price) public { }
}
```

### 5.3 Test Naming Conventions

**Test Function Naming:**
```solidity
// Format: test[FunctionName]_[Condition]
function testCreateListing_Valid() public { }
function testCreateListing_ZeroAddress() public { }
function testCreateListing_InvalidPrice() public { }

// Fuzz tests
function testFuzzCreateListing_Price(uint256 price) public { }

// Failure tests
function testRevertCreateListing_ZeroAddress() public { }
```

### 5.4 Test Coverage Requirements

**Minimum Coverage:**
- **Unit Tests:** All functions must have unit tests
- **Integration Tests:** All workflows must have integration tests
- **Edge Cases:** All edge cases must be tested
- **Failure Cases:** All failure paths must be tested

**Pass Rate:** 100% required (all tests must pass)

### 5.5 Test Best Practices

**Isolation:** Each test should be independent
```solidity
function testCreateListing() public {
    // Don't rely on state from other tests
    // Use setUp() for common setup
}
```

**Explicit Assertions:** Use clear assertions
```solidity
// Good
assertEq(listing.price, expectedPrice);
assertEq(listing.seller, seller);

// Bad
assertTrue(listing.price == expectedPrice); // Less clear
```

**Event Testing:** Test events are emitted correctly
```solidity
vm.expectEmit(true, true, true, true);
emit ListingCreated(listingId, seller, nftContract, tokenId, price);
exchange.createListing(nftContract, tokenId, price, duration);
```

**Revert Testing:** Test custom errors
```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        ERC721NFTExchange__InvalidPrice.selector,
        0,
        MIN_PRICE
    )
);
exchange.createListing(nftContract, tokenId, 0, duration);
```

---

## 6. Gas Optimization Guidelines

### 6.1 Custom Errors

**Always use custom errors instead of require strings:**
```solidity
// Good (~50 gas savings)
error ERC721NFTExchange__InvalidPrice(uint256 price, uint256 minPrice);
if (price < MIN_PRICE) {
    revert ERC721NFTExchange__InvalidPrice(price, MIN_PRICE);
}

// Bad (expensive)
require(price >= MIN_PRICE, "Price too low");
```

**Error Naming:** `ContractName__ErrorName` for consistency

### 6.2 Storage Optimization

**Pack structs efficiently:**
```solidity
// Good (packed into single slot)
struct Listing {
    uint96 price;        // 96 bits
    uint64 duration;     // 64 bits
    uint32 createdAt;    // 32 bits
    ListingStatus status; // 8 bits (enum)
    address seller;      // 160 bits
    // Total: 360 bits = 45 bytes (fits in 2 slots)

    // Better: Use uint96 for price (max ~79 billion ETH)
    // Better: Use uint32 for duration (max 136 years)
    // Better: Use uint32 for createdAt (max 136 years)
}

// Bad (wasted space)
struct Listing {
    uint256 price;      // 256 bits
    uint256 duration;   // 256 bits
    uint256 createdAt;  // 256 bits
    // Total: 768 bits = 96 bytes (4 slots)
}
```

**Use appropriate data types:**
```solidity
// Good
uint32 timestamp;  // Sufficient for timestamps
uint96 amount;     // Sufficient for prices (< 79 billion ETH)
uint8 role;        // For small enums

// Bad
uint256 timestamp; // Wasted space
uint256 role;      // Wasted space
```

### 6.3 Caching Storage Reads

**Cache storage variables in memory:**
```solidity
// Good
function example() public {
    uint256 value = s_value; // SLOAD once
    uint256 result = value * 2;
    uint256 final = result + value;
}

// Bad
function example() public {
    uint256 result = s_value * 2;  // SLOAD
    uint256 final = result + s_value;  // SLOAD again
}
```

### 6.4 Minimal Proxy Pattern

**Use minimal proxies for deployments:**
```solidity
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract Factory {
    address immutable implementation;

    function deploy() external returns (address proxy) {
        proxy = Clones.clone(implementation);
        // ~100x gas savings vs full deployment
    }
}
```

**Benefits:** ~100x gas savings on deployment

### 6.5 Libraries over Inheritance

**Use libraries for code reuse:**
```solidity
// Good (library)
import {PaymentDistributionLib} from "./libraries/PaymentDistributionLib.sol";

function distribute(uint256 amount) internal {
    PaymentDistributionLib.distribute(amount);
}

// Bad (inheritance for utility functions)
contract PaymentHelper {
    function distribute(uint256 amount) internal { }
}

contract MyContract is PaymentHelper {
    // Unnecessary inheritance
}
```

### 6.6 Batch Operations

**Support batch operations where possible:**
```solidity
// Good
function createListingsBatch(
    address[] calldata nftContracts,
    uint256[] calldata tokenIds,
    uint256[] calldata prices
) external {
    for (uint256 i = 0; i < nftContracts.length; i++) {
        createListing(nftContracts[i], tokenIds[i], prices[i]);
    }
}

// Bad (multiple transactions)
// User must call createListing() multiple times
```

---

## 7. Security Requirements

### 7.1 Access Control

**Role-Based Access Control (RBAC):**
```solidity
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Example is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function adminFunction() external onlyRole(ADMIN_ROLE) {
        // Admin-only logic
    }

    function operatorFunction() external onlyRole(OPERATOR_ROLE) {
        // Operator-only logic
    }
}
```

**Function Protection:**
- **Public functions:** Must be protected (role-based or access control)
- **External functions:** Must be protected (role-based or access control)
- **Internal functions:** Assume trusted caller
- **Private functions:** Assume trusted caller

### 7.2 Reentrancy Protection

**Use ReentrancyGuard on all state-changing functions:**
```solidity
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Example is ReentrancyGuard {
    function withdraw() external nonReentrant {
        // Checks
        uint256 amount = s_balances[msg.sender];

        // Effects
        s_balances[msg.sender] = 0;

        // Interactions
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }
}
```

**Checks-Effects-Interactions Pattern:**
1. **Checks:** Validate inputs and conditions
2. **Effects:** Update state variables
3. **Interactions:** Call external contracts

### 7.3 Input Validation

**Validate ALL external inputs:**
```solidity
function createListing(uint256 price, uint256 duration) external {
    // Validate price
    if (price < MIN_PRICE) {
        revert Example__InvalidPrice(price, MIN_PRICE);
    }

    // Validate duration
    if (duration < MIN_DURATION || duration > MAX_DURATION) {
        revert Example__InvalidDuration(duration, MIN_DURATION, MAX_DURATION);
    }

    // Validate ownership
    if (!_ownsNFT(msg.sender, nftContract, tokenId)) {
        revert Example__NotOwner();
    }

    // Validate approval
    if (!_isApproved(msg.sender, nftContract, tokenId)) {
        revert Example__NotApproved();
    }

    // Proceed with listing creation
}
```

**Validation Libraries:**
- Use dedicated validation libraries
- Centralize validation logic
- Test all validation paths

### 7.4 Emergency Controls

**Implement emergency pause functionality:**
```solidity
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Example is Pausable {
    function emergencyPause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function emergencyUnpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    function criticalFunction() external whenNotPaused {
        // Function logic
    }
}
```

### 7.5 Timelock Protection

**Use timelock for critical changes:**
```solidity
contract MarketplaceTimelock {
    uint256 private constant DELAY = 48 hours;

    struct QueuedAction {
        uint256 executeAt;
        bool executed;
    }

    mapping(bytes32 => QueuedAction) private s_queuedActions;

    function queueAction(bytes32 actionId) external onlyRole(TIMELOCK_ADMIN) {
        s_queuedActions[actionId] = QueuedAction({
            executeAt: block.timestamp + DELAY,
            executed: false
        });
    }

    function executeAction(bytes32 actionId) external {
        QueuedAction storage action = s_queuedActions[actionId];
        require(block.timestamp >= action.executeAt, "Too early");
        require(!action.executed, "Already executed");

        action.executed = true;
        // Execute action
    }
}
```

---

## 8. Documentation Requirements

### 8.1 NatSpec Coverage

**Required NatSpec:**
- ✅ All contracts: `@title`, `@notice`, `@dev`
- ✅ All public/external functions: `@notice`, `@dev`, `@params`, `@return`
- ✅ All events: `@notice`, `@params`
- ✅ All errors: `@notice`, `@params` (if applicable)
- ✅ All public state variables: `@notice`

### 8.2 Code Comments

**When to Comment:**
- Complex logic: Explain WHY, not WHAT
- Non-obvious decisions: Explain reasoning
- Workarounds: Explain issue and workaround
- TODO/FIXME: Mark incomplete work

**Comment Style:**
```solidity
// Good: Explains WHY
// We use uint96 for price to fit in one slot with other variables
// Max value: ~79 billion ETH (more than sufficient)
uint96 price;

// Bad: States the obvious
// This is the price
uint256 price;
```

### 8.3 README Requirements

**Every module/directory should have a README explaining:**
- Purpose and functionality
- Key contracts and their roles
- Integration points
- Usage examples

---

## 9. Git Conventions

### 9.1 Commit Messages

**Conventional Commits format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test changes
- `chore`: Build/process changes
- `contract`: Smart contract changes
- `deploy`: Deployment changes
- `security`: Security fixes

**Scopes:**
- `exchange`: Exchange contracts
- `collection`: Collection contracts
- `auction`: Auction contracts
- `fees`: Fee management
- `security`: Security features
- `factory`: Factory contracts
- `libraries`: Library changes
- `validation`: Validation logic
- `access`: Access control

**Examples:**
```
feat(exchange): add bundle trading support
fix(auction): prevent bid overflow in dutch auction
docs(readme): update installation instructions
security(exchange): add reentrancy guard to purchase
```

### 9.2 Pull Request Guidelines

**PR Title:** Use conventional commit format

**PR Description:**
- Summary of changes
- Motivation and context
- Breaking changes (if any)
- Related issues
- Screenshots (if applicable)
- Testing instructions

**PR Checklist:**
- [ ] All tests pass
- [ ] Code formatted (`forge fmt`)
- [ ] NatSpec complete
- [ ] Custom errors used
- [ ] Events emitted for state changes
- [ ] Gas optimizations applied

---

## 10. Code Review Checklist

### 10.1 Before Submitting for Review

**Code Quality:**
- [ ] Follows naming conventions
- [ ] Proper indentation and formatting
- [ ] NatSpec documentation complete
- [ ] No commented-out code
- [ ] No unused variables or imports
- [ ] No magic numbers (use constants)

**Security:**
- [ ] All external calls protected
- [ ] Reentrancy protection where needed
- [ ] Input validation complete
- [ ] Access control implemented
- [ ] Emergency controls considered
- [ ] Timelock for critical changes

**Testing:**
- [ ] All functions have tests
- [ ] Edge cases covered
- [ ] Failure paths tested
- [ ] Events tested
- [ ] Custom errors tested
- [ ] All tests pass (100%)

**Gas Optimization:**
- [ ] Custom errors used
- [ ] Storage packed efficiently
- [ ] Storage reads cached
- [ ] Appropriate data types
- [ ] No unnecessary computations

### 10.2 During Code Review

**What to Look For:**
1. Security vulnerabilities
2. Logic errors
3. Gas optimization opportunities
4. Code organization and clarity
5. Test coverage
6. Documentation completeness
7. Naming conventions
8. Breaking changes

---

## 11. Tools and Automation

### 11.1 Required Tools

**Foundry:**
```bash
forge build    # Compile contracts
forge test     # Run tests
forge fmt      # Format code
forge snapshot # Gas snapshots
forge coverage # Coverage report
```

**Linting:**
```bash
forge fmt --check  # Check formatting
```

### 11.2 Pre-commit Hooks

**Install pre-commit hooks:**
```bash
pnpm install
```

**Hooks Run:**
- Format check (`forge fmt --check`)
- Test execution (`forge test`)
- Commit lint (conventional commits)

### 11.3 CI/CD

**GitHub Actions Workflow:**
1. On pull request: Run all tests
2. On push to main: Run tests + deployment
3. On release: Deploy to testnet/mainnet

---

## 12. Best Practices Summary

### DO:
- ✅ Follow RED-GREEN-REFACTOR methodology
- ✅ Write tests BEFORE implementation
- ✅ Use custom errors (not require strings)
- ✅ Add NatSpec to ALL contracts/functions/events/errors
- ✅ Follow naming conventions consistently
- ✅ Use ReentrancyGuard on state-changing functions
- ✅ Validate ALL external inputs
- ✅ Optimize gas (custom errors, packing, caching)
- ✅ Write integration tests for workflows
- ✅ Use libraries for reusable logic
- ✅ Follow conventional commit format

### DON'T:
- ❌ Write implementation before tests
- ❌ Use require strings (use custom errors)
- ❌ Skip NatSpec documentation
- ❌ Use inconsistent naming
- ❌ Forget reentrancy protection
- ❌ Skip input validation
- ❌ Leave commented-out code
- ❌ Commit failing tests
- ❌ Use string reverts
- ❌ Ignore gas optimization
- ❌ Skip security reviews

---

## 13. Enforcement

### Code Review Process
1. Author creates pull request
2. CI/CD runs automated checks (tests, formatting)
3. Reviewer reviews against this checklist
4. Author addresses feedback
5. Reviewer approves when all criteria met
6. Code merged to main

### Failed Checks
If any check fails:
1. Block merge until fixed
2. Author must address issues
3. Re-run checks
4. Re-review required for security changes

---

**Document Owner:** Development Team
**Last Updated:** 2026-01-07
**Next Review:** Monthly or as needed
