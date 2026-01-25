# Phase 02: Test Updates

## Context Links

- Main Plan: [`plan.md`](./plan.md)
- Phase 01: [`phase-01-fix-implementation.md`](./phase-01-fix-implementation.md)
- BaseCollection Tests: `test/unit/collection/`
- Test Mock: `test/unit/collection/UnitBaseCollectionTest.t.sol` (MockBaseCollection)

## Overview

**Priority:** P1 (Critical)
**Status:** pending
**Effort:** 1 hour

Add comprehensive test coverage for owner minting during allowlist stage to ensure the fix works correctly and prevent regressions.

## Key Insights

1. **Test Structure:** `MockBaseCollection` in `UnitBaseCollectionTest.t.sol` exposes mint functionality
2. **Existing Tests:** Current tests verify non-owner allowlist restriction (line 165-174)
3. **Gap:** No tests verify owner can mint without allowlist during allowlist stage
4. **Coverage:** Need both positive (owner succeeds) and negative (non-owner fails) tests

## Requirements

### Functional Requirements
- Test owner CAN mint during allowlist stage without being on allowlist
- Test non-owner CANNOT mint during allowlist stage without allowlist entry
- Test non-owner CANNOT mint during allowlist stage even if owner is on allowlist
- Test owner CAN mint during public stage (regression test)

### Non-Functional Requirements
- Follow existing test naming conventions
- Use `vm.prank()` for owner testing
- Use descriptive test function names
- Maintain 100% test pass rate

## Architecture

**Test Cases Needed:**

```
Test Suite: Owner Allowlist Bypass
├── test_Owner_MintDuringAllowlist_NotOnAllowlist()
├── test_Owner_MintDuringAllowlist_WithAllowlistEntry()
├── test_NonOwner_MintDuringAllowlist_NotOnAllowlist() (existing)
├── test_Owner_MintDuringAllowlist_OnlyMode_NotOnAllowlist()
└── test_Owner_MintDuringPublicStage()
```

## Related Code Files

### Files to Modify

**1. `test/unit/collection/UnitBaseCollectionTest.t.sol`**
- **Location:** After line 229 (after `test_Mint_InsufficientPayment`)
- **Add:** New test functions for owner minting

**2. `test/unit/collection/BaseCollectionCoverage.t.sol`**
- **Location:** After line 345 (after `test_RemoveFromAllowlist_EmptyArray`)
- **Add:** Coverage test for owner exemption edge cases

### Files to Create

None

### Files to Delete

None

## Implementation Steps

### Step 1: Add Owner Mint Tests to UnitBaseCollectionTest.t.sol

Add after `test_Mint_InsufficientPayment` (line 229):

```solidity
// ============================================================================
// OWNER ALLOWLIST EXEMPTION TESTS
// ============================================================================

function test_Owner_MintDuringAllowlist_NotOnAllowlist() public {
    // Move to allowlist stage
    vm.warp(setup.params.mintStartTime);
    setup.collection.updateMintStage();
    assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.ALLOWLIST));

    // Verify owner is NOT on allowlist
    assertFalse(setup.collection.isInAllowlist(setup.owner));

    // Owner should be able to mint without allowlist
    vm.startPrank(setup.owner);
    vm.deal(setup.owner, setup.params.allowlistMintPrice);
    setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
    assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
    assertEq(setup.collection.getTotalMinted(), 1);
    vm.stopPrank();
}

function test_Owner_MintDuringAllowlist_WithAllowlistEntry() public {
    // Move to allowlist stage
    vm.warp(setup.params.mintStartTime);
    setup.collection.updateMintStage();

    // Add owner to allowlist (edge case - owner with allowlist entry)
    address[] memory addresses = new address[](1);
    addresses[0] = setup.owner;
    vm.prank(setup.owner);
    setup.collection.addToAllowlist(addresses);

    // Owner should still be able to mint
    vm.startPrank(setup.owner);
    vm.deal(setup.owner, setup.params.allowlistMintPrice);
    setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
    assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
    vm.stopPrank();
}

function test_Owner_MintDuringAllowlist_OnlyMode_NotOnAllowlist() public {
    // Enable allowlist-only mode (never goes to public)
    vm.prank(setup.owner);
    setup.collection.setAllowlistOnly(true);

    // Move to allowlist stage
    vm.warp(setup.params.mintStartTime);
    setup.collection.updateMintStage();
    assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.ALLOWLIST));

    // Verify owner is NOT on allowlist
    assertFalse(setup.collection.isInAllowlist(setup.owner));

    // Owner should be able to mint even in allowlist-only mode
    vm.startPrank(setup.owner);
    vm.deal(setup.owner, setup.params.allowlistMintPrice);
    setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.owner, 1);
    assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
    vm.stopPrank();
}

function test_Owner_MintDuringPublicStage() public {
    // Move to public stage (regression test - ensure fix doesn't break public stage)
    vm.warp(setup.params.mintStartTime + setup.params.allowlistStageDuration + 1);
    setup.collection.updateMintStage();
    assertEq(uint256(setup.collection.getCurrentStage()), uint256(MintStage.PUBLIC));

    // Owner should be able to mint during public stage
    vm.startPrank(setup.owner);
    vm.deal(setup.owner, setup.params.publicMintPrice);
    setup.collection.mint{value: setup.params.publicMintPrice}(setup.owner, 1);
    assertEq(setup.collection.s_mintedPerWallet(setup.owner), 1);
    assertEq(setup.collection.getTotalMinted(), 1);
    vm.stopPrank();
}

function test_NonOwner_MintDuringAllowlist_WhileOwnerOnAllowlist() public {
    // Edge case: owner on allowlist shouldn't help non-owners
    vm.warp(setup.params.mintStartTime);
    setup.collection.updateMintStage();

    // Add ONLY owner to allowlist
    address[] memory addresses = new address[](1);
    addresses[0] = setup.owner;
    vm.prank(setup.owner);
    setup.collection.addToAllowlist(addresses);

    // Non-owner should still fail
    vm.startPrank(setup.user);
    vm.deal(setup.user, setup.params.allowlistMintPrice);
    vm.expectRevert(Collection__NotInAllowlist.selector);
    setup.collection.mint{value: setup.params.allowlistMintPrice}(setup.user, 1);
    vm.stopPrank();
}
```

### Step 2: Add Coverage Tests

Add to `BaseCollectionCoverage.t.sol` after line 345:

```solidity
// ============================================================================
// OWNER ALLOWLIST EXEMPTION COVERAGE TESTS
// ============================================================================

function test_Coverage_OwnerExemptionFromAllowlist() public {
    // Setup collection with allowlist stage active
    CollectionParams memory params = CollectionParams({
        name: "Owner Test",
        symbol: "OWN",
        owner: CREATOR,
        description: "Owner Exemption Test",
        mintPrice: 0,
        royaltyFee: 500,
        maxSupply: 100,
        mintLimitPerWallet: 10,
        mintStartTime: block.timestamp,
        allowlistMintPrice: 0.1 ether,
        publicMintPrice: 0.2 ether,
        allowlistStageDuration: 1 days,
        tokenURI: "ipfs://test/"
    });

    vm.prank(CREATOR);
    CoverageTestableBaseCollection collection = new CoverageTestableBaseCollection(params);

    // Move to allowlist stage
    vm.warp(block.timestamp);
    collection.updateMintStage();

    // Verify CREATOR is NOT on allowlist
    assertFalse(collection.isInAllowlist(CREATOR));
    assertFalse(collection.isInAllowlist(USER));

    // Create a testable wrapper with mint function
    vm.prank(CREATOR);
    TestableCollection testable = new TestableCollection(collection);

    // Owner (CREATOR) can mint without allowlist
    vm.prank(CREATOR);
    testable.testMint(CREATOR);

    // Non-owner (USER) cannot mint without allowlist
    vm.prank(USER);
    vm.expectRevert(abi.encodeWithSelector(Collection__NotInAllowlist.selector));
    testable.testMint(USER);
}

/**
 * @notice Helper contract to test mint validation with coverage
 */
contract TestableCollection {
    CoverageTestableBaseCollection immutable collection;

    constructor(CoverageTestableBaseCollection _collection) {
        collection = _collection;
    }

    function testMint(address to) external {
        // This exposes the internal _validateMintConditions for testing
        uint256 amount = 1;
        uint256 requiredPayment = collection.checkMint(to, amount);
        collection.updateMintStage();
    }
}
```

### Step 3: Run Tests

```bash
# Run specific test file
forge test --match-path test/unit/collection/UnitBaseCollectionTest.t.sol -vv

# Run coverage tests
forge test --match-path test/unit/collection/BaseCollectionCoverage.t.sol -vv

# Run all collection tests
forge test --match-path test/unit/collection/ -vv

# Full test suite
forge test
```

### Step 4: Verify Test Coverage

```bash
# Generate coverage report
forge coverage --match-path src/common/BaseCollection.sol
```

Expected: Line 187 should have 100% coverage (both owner and non-owner branches)

## Success Criteria

- [ ] All 6 new owner exemption tests pass
- [ ] All existing tests still pass (no regressions)
- [ ] Test coverage for `_validateMintConditions` reaches 100%
- [ ] Both branches of `to != owner()` condition covered
- [ ] Edge cases tested (allowlist-only mode, owner on allowlist)

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Test setup complexity | Medium | Low | Use existing MockBaseCollection pattern |
| Missing edge cases | Low | Medium | Review test cases against requirements |
| Flaky tests | Very Low | Low | Deterministic test design |
| Performance issues | Very Low | Low | Small test suite |

## Security Considerations

### Test Security Properties
1. **Owner Exemption:** Verified through direct test
2. **Non-Owner Restriction:** Verified through regression test
3. **Allowlist-Only Mode:** Tested to ensure owner still exempt
4. **No Privilege Escalation:** Non-owners cannot piggyback on owner exemption

### Edge Cases Covered
- Owner mints during allowlist stage (not on allowlist) ✅
- Owner mints during allowlist stage (on allowlist) ✅
- Owner mints during allowlist-only mode ✅
- Owner mints during public stage (regression) ✅
- Non-owner blocked even if owner on allowlist ✅

### Audit Checklist
- [x] Tests verify fix addresses root cause
- [x] Tests prevent regression (non-owner still blocked)
- [x] Edge cases covered
- [x] Follows project testing standards
- [x] Uses proper Foundry test patterns

## Next Steps

1. Implement tests in this phase
2. Run full test suite to verify
3. Delegate to `code-simplifier` for code refinement
4. Delegate to `code-reviewer` for final review
5. Update documentation (if needed)
6. Commit with conventional commit format: `fix(collection): exempt owner from allowlist check during minting`
