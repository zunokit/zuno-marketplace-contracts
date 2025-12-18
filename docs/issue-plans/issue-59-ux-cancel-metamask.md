# Issue #59: UX for User When Cancel in MetaMask Too Bad

## Issue Summary
**Title**: UX for user when `cancel` in Metamask too bad

**Error Example**:
```
Failed for collection tokens [1]: user rejected action (action="sendTransaction", reason="rejected",
info={ "error": { "code": 4001, "message": "ethers-user-denied: MetaMask Tx Signature: User denied transaction signature." }})
```

**Affected Components**:
- `E:/zuno-marketplace-sdk/src/utils/errors.ts`
- `E:/zuno-marketplace-sdk/src/utils/helpers.ts`
- `E:/zuno-marketplace-sdk/src/utils/transactions.ts`
- Frontend error display

## Root Cause Analysis

### Current Behavior
The SDK currently:
1. Catches user rejection errors correctly
2. Identifies them via `message.includes('user rejected')`
3. Creates a `ZunoSDKError` with code `TRANSACTION_FAILED`
4. Message: "User rejected the transaction"

### Problem
While technically correct, the error message and handling is:
1. **Too technical** - Shows raw error codes and stack traces
2. **Alarming** - Uses word "Failed" which sounds like system error
3. **Not actionable** - Doesn't tell user what to do next
4. **Confusing** - User cancelled intentionally, but sees "error"

### Current Code Analysis

**`src/utils/helpers.ts`**:
```typescript
export function parseTransactionError(error: unknown): ZunoSDKError {
  const message = error instanceof Error ? error.message : String(error);

  if (message.includes('user rejected')) {
    return new ZunoSDKError(
      ErrorCodes.TRANSACTION_FAILED,
      'User rejected the transaction'
    );
  }
  // ...
}
```

## Implementation Plan

### Phase 1: Add Specific Error Code for User Rejection
```typescript
// errors.ts
export const ErrorCodes = {
  // ... existing codes
  TRANSACTION_FAILED: 'TRANSACTION_FAILED',
  USER_REJECTED: 'USER_REJECTED',  // NEW
  USER_CANCELLED: 'USER_CANCELLED', // Alias for clarity
  // ...
} as const;
```

### Phase 2: Update Error Parsing
```typescript
// helpers.ts
export function parseTransactionError(error: unknown): ZunoSDKError {
  const message = error instanceof Error ? error.message : String(error);

  // Check for user rejection first
  if (
    message.includes('user rejected') ||
    message.includes('user denied') ||
    message.includes('User denied transaction') ||
    (error as any)?.code === 4001 // MetaMask rejection code
  ) {
    return new ZunoSDKError(
      ErrorCodes.USER_REJECTED,
      'Transaction cancelled',
      {
        isUserAction: true,
        suggestion: 'Click the button again if you want to retry',
        severity: 'info' // Not an error, just user action
      }
    );
  }

  // ... rest of error handling
}
```

### Phase 3: Add User-Friendly Error Messages
```typescript
// errors.ts
export const UserFriendlyMessages: Record<string, ErrorMessage> = {
  [ErrorCodes.USER_REJECTED]: {
    title: 'Transaction Cancelled',
    message: 'You cancelled the transaction in your wallet.',
    suggestion: 'If this was a mistake, you can try again.',
    icon: 'info', // Not error icon
    color: 'neutral' // Not red
  },
  [ErrorCodes.TRANSACTION_FAILED]: {
    title: 'Transaction Failed',
    message: 'The transaction could not be completed.',
    suggestion: 'Please check your wallet balance and try again.',
    icon: 'error',
    color: 'red'
  },
  // ... more messages
};
```

### Phase 4: SDK Error Class Enhancement
```typescript
// errors.ts
export class ZunoSDKError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly metadata?: {
      isUserAction?: boolean;
      suggestion?: string;
      severity?: 'error' | 'warning' | 'info';
      retryable?: boolean;
    }
  ) {
    super(message);
    this.name = 'ZunoSDKError';
  }

  /**
   * Returns user-friendly error info for display
   */
  toUserMessage(): UserFriendlyMessage {
    return UserFriendlyMessages[this.code] || {
      title: 'Error',
      message: this.message,
      suggestion: 'Please try again or contact support.',
      icon: 'error',
      color: 'red'
    };
  }

  /**
   * Check if this was a user-initiated cancellation
   */
  isUserCancellation(): boolean {
    return this.code === ErrorCodes.USER_REJECTED ||
           this.metadata?.isUserAction === true;
  }
}
```

### Phase 5: Frontend Integration Guide
Provide guidance for frontend developers:

```typescript
// Example React usage
try {
  await sdk.exchange.buyNFT(listingId);
} catch (error) {
  if (error instanceof ZunoSDKError) {
    if (error.isUserCancellation()) {
      // Show info toast, not error
      toast.info('Transaction cancelled', {
        description: 'You can try again when ready'
      });
    } else {
      // Show error toast
      toast.error(error.toUserMessage().title, {
        description: error.toUserMessage().message
      });
    }
  }
}
```

## Files to Modify

| File | Change |
|------|--------|
| `E:/zuno-marketplace-sdk/src/utils/errors.ts` | Add `USER_REJECTED` code, enhance `ZunoSDKError` class |
| `E:/zuno-marketplace-sdk/src/utils/helpers.ts` | Update `parseTransactionError` function |
| `E:/zuno-marketplace-sdk/src/types/index.ts` | Add new types for error metadata |
| `E:/zuno-marketplace-sdk/README.md` | Document error handling best practices |

## User-Friendly Message Guidelines

### For User Rejection:
- **Title**: "Transaction Cancelled" (not "Failed" or "Error")
- **Tone**: Neutral, informative
- **Color**: Blue/Gray (not red)
- **Icon**: Info icon (not error/warning)
- **Suggestion**: "Click again to retry" or similar

### For Actual Errors:
- **Title**: Specific error description
- **Tone**: Apologetic but helpful
- **Color**: Red/Orange
- **Icon**: Error/Warning icon
- **Suggestion**: Actionable next steps

## Test Cases
```typescript
describe('Error Handling', () => {
  it('should identify MetaMask rejection by message', () => {
    const error = new Error('user rejected action');
    const parsed = parseTransactionError(error);
    expect(parsed.code).toBe(ErrorCodes.USER_REJECTED);
    expect(parsed.isUserCancellation()).toBe(true);
  });

  it('should identify MetaMask rejection by code 4001', () => {
    const error = { code: 4001, message: 'User denied' };
    const parsed = parseTransactionError(error);
    expect(parsed.code).toBe(ErrorCodes.USER_REJECTED);
  });

  it('should return user-friendly message for rejection', () => {
    const error = parseTransactionError(new Error('user rejected'));
    const message = error.toUserMessage();
    expect(message.severity).toBe('info');
    expect(message.title).toBe('Transaction Cancelled');
  });
});
```

## Acceptance Criteria
1. User rejection shows "Transaction Cancelled" not "Failed"
2. Error severity is "info" for user actions, "error" for system failures
3. UI can distinguish between user actions and actual errors
4. Suggestions are actionable and helpful
5. No technical jargon in user-facing messages
6. Consistent across all SDK modules
