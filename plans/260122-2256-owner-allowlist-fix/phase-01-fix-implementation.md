# Phase 01: Fix Implementation

## Context Links

- Main Plan: [`plan.md`](./plan.md)
- BaseCollection: `src/common/BaseCollection.sol`
- CollectionErrors: `src/errors/CollectionErrors.sol`
- Ownable (OZ): `lib/openzeppelin-contracts/contracts/access/Ownable.sol`

## Overview

**Priority:** P1 (Critical)
**Status:** pending
**Effort:** 30 minutes

Implement one-line fix to exempt contract owner from allowlist check during minting.

## Key Insights

1. **Root Cause:** `_validateMintConditions()` at lines 186-188 lacks owner exemption
2. **Pattern Match:** Other contracts use `msg.sender != owner()` pattern for exemptions
3. **Minimal Change:** Single condition addition, no structural changes needed
4. **Gas Impact:** Negligible (one additional address comparison)

## Requirements

### Functional Requirements
- Owner MUST be able to mint during allowlist stage without allowlist entry
- Non-owner MUST still require allowlist access during allowlist stage
- All other mint validation logic MUST remain unchanged

### Non-Functional Requirements
- No gas regression beyond negligible comparison cost
- Maintain code readability
- Follow existing code style (short-circuit evaluation)

## Architecture

**Current Flow:**
```
_validateMintConditions(to, amount)
  ├─ Check minting active
  ├─ Check wallet limits
  └─ Check allowlist stage
       └─ if (ALLOWLIST && !s_allowlist[to]) REVERT  ❌ Owner blocked
```

**Fixed Flow:**
```
_validateMintConditions(to, amount)
  ├─ Check minting active
  ├─ Check wallet limits
  └─ Check allowlist stage
       └─ if (ALLOWLIST && to != owner() && !s_allowlist[to]) REVERT  ✅ Owner exempt
```

## Related Code Files

### Files to Modify

**1. `src/common/BaseCollection.sol`**
- **Location:** Lines 186-188
- **Function:** `_validateMintConditions(address to, uint256 amount) internal`
- **Change:** Add owner exemption condition

**Before:**
```solidity
// Check allowlist if in allowlist stage
if (s_currentStage == MintStage.ALLOWLIST) {
    if (!s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

**After:**
```solidity
// Check allowlist if in allowlist stage (owner exempt)
if (s_currentStage == MintStage.ALLOWLIST) {
    if (to != owner() && !s_allowlist[to]) revert Collection__NotInAllowlist();
}
```

### Files to Create

None

### Files to Delete

None

## Implementation Steps

1. **Backup Current State**
   ```bash
   git diff src/common/BaseCollection.sol
   ```

2. **Apply Fix**
   - Open `src/common/BaseCollection.sol`
   - Navigate to line 187
   - Replace condition from `if (!s_allowlist[to])` to `if (to != owner() && !s_allowlist[to])`

3. **Update Comment**
   - Change line 185 comment from "Check allowlist if in allowlist stage"
   - To: "Check allowlist if in allowlist stage (owner exempt)"

4. **Verify Syntax**
   ```bash
   forge build
   ```

5. **Check Gas Diff**
   ```bash
   forge snapshot --diff-base .gas-snapshot
   ```

## Success Criteria

- [ ] Code compiles without errors
- [ ] Owner exemption condition added to line 187
- [ ] Comment updated to reflect owner exemption
- [ ] Gas snapshot shows minimal change (<50 gas per mint)
- [ ] No other code modified

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Syntax error | Low | Medium | Compile check before commit |
| Gas regression | Very Low | Low | Gas snapshot comparison |
| Breaking existing tests | Low | High | Test suite validation in Phase 02 |
| Introduces new bug | Very Low | Medium | Code review |

## Security Considerations

### Access Control
- **Owner Exemption:** Safe - follows standard Ownable pattern
- **No Privilege Escalation:** Owner already has full control via `onlyOwner` functions
- **No Reentrancy:** Pure validation check, no state changes

### Edge Cases Handled
1. **Owner transfers ownership:** New owner inherits exemption (correct behavior)
2. **Owner address(0):** Impossible (Ownable prevents zero address owner)
3. **Renounce ownership:** Possible - contract becomes immutable, no owner to exempt

### Audit Checklist
- [x] Uses standard `owner()` from OpenZeppelin Ownable
- [x] Short-circuit evaluation (`to != owner()` evaluated first)
- [x] No additional storage reads
- [x] No external calls
- [x] Revert with appropriate error (`Collection__NotInAllowlist`)

## Next Steps

1. Complete this phase
2. Proceed to [Phase 02: Test Updates](./phase-02-test-updates.md)
3. Delegate to `code-simplifier` agent for refinement
4. Delegate to `tester` agent for validation
