# Query Keys & Query Options Research Report
**Date:** 2026-01-12
**Repository:** zuno-marketplace-sdk
**Issue:** #79 - Improve Query Keys Using Query Options
**Researcher:** Subagent Researcher

---

## Executive Summary

Current implementation uses **inline query keys** (string arrays) scattered across hooks. TanStack Query v5's **queryOptions pattern** provides type-safe, reusable query definitions. SDK already uses this pattern for ABI queries (ZunoAPIClient.ts) but **not** for marketplace hooks (Exchange, Auction, Collection).

**Key Finding:** Only 4 query options functions exist (ABI-related). 21+ hooks use inline query keys. Migration opportunity: **HIGH**.

---

## 1. Inventory of Query Hooks

### All React Hooks Using TanStack Query

| Hook File | LOC | useQuery | useMutation | Query Keys |
|-----------|-----|----------|-------------|------------|
| `useExchange.ts` | 127 | 3 | 6 | Inline strings |
| `useAuction.ts` | 169 | 3 | 10 | Inline strings |
| `useCollection.ts` | 280 | 7 | 10 | Inline strings |
| `useABIs.ts` | 103 | 4 | 0 | **Uses queryOptions ✅** |
| `useApprove.ts` | 95 | 0 | 2 | Inline strings |
| `useBalance.ts` | 18 | 1 (wagmi) | 0 | N/A (wagmi) |
| `useWallet.ts` | 115 | 0 (wagmi) | 0 | N/A (wagmi) |
| `useZunoSDK.ts` | 52 | 0 | 0 | N/A |
| `useZunoLogger.ts` | 39 | 0 | 0 | N/A |
| `useProviderSync.ts` | 151 | 0 | 0 | N/A |

**Total:** 18 query hooks, 28 mutations, **4 using queryOptions pattern**.

---

## 2. Current Query Key Patterns

### 2.1 Inline Query Keys (PROBLEMATIC)

**Location:** `src/react/hooks/useExchange.ts`
```typescript
// ❌ Inline, not reusable, no type safety
export function useListings(collectionAddress?: string) {
  return useQuery({
    queryKey: ['listings', collectionAddress],
    queryFn: () => sdk.exchange.getListings(collectionAddress!),
    enabled: !!collectionAddress,
  });
}

export function useListingsBySeller(seller?: string) {
  return useQuery({
    queryKey: ['listings', 'seller', seller],
    queryFn: () => sdk.exchange.getListingsBySeller(seller!),
    enabled: !!seller,
  });
}
```

**Location:** `src/react/hooks/useAuction.ts`
```typescript
// ❌ Inconsistent hierarchy: 'auction' vs 'auctions'
export function useAuctionDetails(auctionId?: string) {
  return useQuery({
    queryKey: ['auction', auctionId],
    queryFn: () => sdk.auction.getAuctionFromFactory(auctionId!),
  });
}
```

**Location:** `src/react/hooks/useCollection.ts`
```typescript
// ❌ Mixed patterns
export function useCollectionInfo(address?: string) {
  return useQuery({
    queryKey: ['collection', address],
    queryFn: () => sdk.collection.getCollectionInfo(address!),
  });
}

export function useIsInAllowlist(collectionAddress?: string, userAddress?: string) {
  return useQuery({
    queryKey: ['allowlist', collectionAddress, userAddress],
    queryFn: () => sdk.collection.isInAllowlist(collectionAddress!, userAddress!),
  });
}
```

### 2.2 Query Options Pattern (CORRECT)

**Location:** `src/core/ZunoAPIClient.ts` (lines 349-409)
```typescript
// ✅ Type-safe, reusable, co-located
export function createABIQueryOptions(
  client: ZunoAPIClient,
  contractName: string,
  network: string,
  cacheConfig?: CacheConfig
) {
  return {
    queryKey: abiQueryKeys.detail(contractName, network),
    queryFn: () => client.getABI(contractName, network),
    staleTime: cacheConfig?.ttl ?? DEFAULT_CACHE_TIMES.STALE_TIME,
    gcTime: cacheConfig?.gcTime ?? DEFAULT_CACHE_TIMES.GC_TIME,
    retry: 3,
    retryDelay: (attemptIndex: number) => Math.min(1000 * 2 ** attemptIndex, 30000),
  };
}
```

**Usage:** `src/react/hooks/useABIs.ts` (line 16)
```typescript
export function useABI(contractType: ContractType, network: string) {
  const sdk = useZuno();
  const apiClient = sdk.getAPIClient();
  return useQuery(createABIQueryOptions(apiClient, contractType, network));
}
```

---

## 3. Query Key Factory Pattern (CURRENT STATE)

**Location:** `src/core/ZunoAPIClient.ts` (lines 67-78)
```typescript
// Only exists for ABI queries
export const abiQueryKeys = {
  all: ['abs'] as const,
  lists: () => [...abiQueryKeys.all, 'list'] as const,
  list: (filters: string) => [...abiQueryKeys.lists(), { filters }] as const,
  details: () => [...abiQueryKeys.all, 'detail'] as const,
  detail: (contractName: string, network: string) =>
    [...abiQueryKeys.details(), contractName, network] as const,
  byId: (abiId: string) => [...abiQueryKeys.details(), 'byId', abiId] as const,
  contracts: (address: string, network: string) =>
    ['contracts', address, network] as const,
  networks: () => ['networks'] as const,
};
```

**Missing:** No query key factories for Exchange, Auction, or Collection.

---

## 4. Issues with Current Implementation

### 4.1 Type Safety Violations
```typescript
// ❌ No autocomplete, no type checking
queryClient.invalidateQueries({ queryKey: ['listings'] });

// ❌ Typo prone
queryKey: ['listngs', address]  // typo not caught
```

### 4.2 Invalidation Scattered
**Exchange invalidations:** 6 occurrences across `useExchange.ts`
```typescript
// Repeated in every mutation
onSuccess: () => {
  queryClient.invalidateQueries({ queryKey: ['listings'] });
},
```

**Auction invalidations:** 15 occurrences across `useAuction.ts`
```typescript
onSuccess: (_, variables) => {
  queryClient.invalidateQueries({ queryKey: ['auction', variables.auctionId] });
  queryClient.invalidateQueries({ queryKey: ['auctions'] });
},
```

**Collection invalidations:** 14 occurrences across `useCollection.ts`

### 4.3 Key Hierarchy Inconsistencies
```typescript
// Exchange: ['listings', collectionAddress]
// Auction: ['auction', auctionId] vs ['auctions'] (singular vs plural)
// Collection: ['collection', address] vs ['collections']
// Allowlist: ['allowlist', collectionAddress, userAddress]
// Approvals: ['approvals', address]
```

### 4.4 No Co-location
Query keys defined inline in hooks, separate from query functions. Violates TanStack Query best practice.

---

## 5. TanStack Query v5 Query Options Best Practices

### 5.1 Official Documentation Guidance
**Source:** [TanStack Query v5 Query Options Guide](https://tanstack.com/query/v5/docs/react/guides/query-options)

> **"queryOptions is one of the best ways to share queryKey and queryFn between multiple places, yet keep them co-located to one another."**

### 5.2 2025 Best Practices

From community research ([source](https://medium.com/@jmytwenty8/why-queryoptions-will-change-how-you-use-tanstack-query-141608dd5c3c)):

**Benefits:**
1. **Type Safety** - Prevent bugs through autocomplete
2. **Consistency** - Uniform pattern across app
3. **Reusability** - Share in hooks, prefetching, server rendering
4. **Co-location** - Query key + function + config together

**Query Factory Pattern:**
```typescript
// ✅ Recommended pattern
export const listingsQueryOptions = (collectionAddress: string) => ({
  queryKey: ['listings', collectionAddress] as const,
  queryFn: () => sdk.exchange.getListings(collectionAddress),
  staleTime: 5000,
});

// Use in hook
export function useListings(address: string) {
  return useQuery(listingsQueryOptions(address));
}

// Use in prefetch
await queryClient.prefetchQuery(listingsQueryOptions(address));
```

### 5.3 Query Key Factory Best Practices
```typescript
// ✅ Hierarchical, type-safe factory
export const exchangeQueryKeys = {
  all: ['exchange'] as const,
  listings: () => [...exchangeQueryKeys.all, 'listings'] as const,
  listing: (id: string) => [...exchangeQueryKeys.listings(), id] as const,
  listingsByCollection: (address: string) =>
    [...exchangeQueryKeys.listings(), 'collection', address] as const,
} as const;
```

---

## 6. Recommended Implementation Pattern

### 6.1 File Structure
```
src/react/query-keys/
├── index.ts                    # Barrel export
├── exchange.query-keys.ts      # Exchange query factory + options
├── auction.query-keys.ts       # Auction query factory + options
├── collection.query-keys.ts    # Collection query factory + options
└── types.ts                    # Shared types
```

### 6.2 Query Key Factory Example
```typescript
// src/react/query-keys/exchange.query-keys.ts
export const exchangeQueryKeys = {
  all: ['exchange'] as const,
  listings: () => [...exchangeQueryKeys.all, 'listings'] as const,
  listing: (listingId: string) =>
    [...exchangeQueryKeys.listings(), listingId] as const,
  listingsByCollection: (collectionAddress: string) =>
    [...exchangeQueryKeys.listings(), 'collection', collectionAddress] as const,
  listingsBySeller: (sellerAddress: string) =>
    [...exchangeQueryKeys.listings(), 'seller', sellerAddress] as const,
} as const;
```

### 6.3 Query Options Example
```typescript
// src/react/query-keys/exchange.query-keys.ts
import type { QueryClient } from '@tanstack/react-query';
import type { ExchangeModule } from '../../modules/ExchangeModule';

export function listingsQueryOptions(
  sdk: { exchange: ExchangeModule },
  collectionAddress: string
) {
  return {
    queryKey: exchangeQueryKeys.listingsByCollection(collectionAddress),
    queryFn: () => sdk.exchange.getListings(collectionAddress),
    staleTime: 10000, // 10 seconds
  } as const;
}

export function listingQueryOptions(
  sdk: { exchange: ExchangeModule },
  listingId: string
) {
  return {
    queryKey: exchangeQueryKeys.listing(listingId),
    queryFn: () => sdk.exchange.getListing(listingId),
    staleTime: 5000, // 5 seconds
  } as const;
}
```

### 6.4 Hook Refactor Example
```typescript
// BEFORE: src/react/hooks/useExchange.ts
export function useListings(collectionAddress?: string) {
  const sdk = useZuno();
  return useQuery({
    queryKey: ['listings', collectionAddress],
    queryFn: () => sdk.exchange.getListings(collectionAddress!),
    enabled: !!collectionAddress,
  });
}

// AFTER: src/react/hooks/useExchange.ts
import { listingsQueryOptions } from '../query-keys/exchange.query-keys';

export function useListings(collectionAddress?: string) {
  const sdk = useZuno();
  return useQuery({
    ...listingsQueryOptions(sdk, collectionAddress!),
    enabled: !!collectionAddress,
  });
}
```

### 6.5 Simplified Invalidation
```typescript
// BEFORE: Scattered inline keys
onSuccess: () => {
  queryClient.invalidateQueries({ queryKey: ['listings'] });
},

// AFTER: Type-safe factory
onSuccess: () => {
  queryClient.invalidateQueries({
    queryKey: exchangeQueryKeys.listings(),
  });
},
```

---

## 7. Migration Plan

### Phase 1: Foundation (1-2 days)
1. Create `src/react/query-keys/` directory
2. Create query key factories for Exchange, Auction, Collection
3. Add type definitions
4. Export from barrel file
5. **DO NOT refactor hooks yet**

### Phase 2: Exchange Hooks (1 day)
1. Create `exchange.query-keys.ts` with query options
2. Refactor `useExchange.ts` mutations
3. Refactor `useListings`, `useListingsBySeller`, `useListing`
4. Test with existing test suite
5. Update docs

### Phase 3: Auction Hooks (1 day)
1. Create `auction.query-keys.ts` with query options
2. Refactor `useAuction.ts` mutations
3. Refactor query hooks
4. Test
5. Update docs

### Phase 4: Collection Hooks (1 day)
1. Create `collection.query-keys.ts` with query options
2. Refactor `useCollection.ts` mutations
3. Refactor query hooks
4. Test
5. Update docs

### Phase 5: Cleanup (0.5 day)
1. Remove inline query keys
2. Export new query keys from main SDK
3. Update README examples
4. Add migration guide to CHANGELOG

**Total Estimate:** 4.5 days

---

## 8. Benefits of New Approach

### 8.1 Type Safety
```typescript
// ✅ Autocomplete, type errors
queryClient.invalidateQueries({
  queryKey: exchangeQueryKeys.listings(),  // typo caught
});
```

### 8.2 Reusability
```typescript
// Use in hook
useQuery(listingsQueryOptions(sdk, address))

// Use in prefetch
await queryClient.prefetchQuery(listingsQueryOptions(sdk, address))

// Use in SSR
await queryClient.prefetchQuery(listingsQueryOptions(sdk, address))
```

### 8.3 Centralized Configuration
```typescript
// Change stale time in one place
export function listingsQueryOptions(...) {
  return {
    queryKey: ...,
    queryFn: ...,
    staleTime: 10000,  // single source of truth
  };
}
```

### 8.4 Predictable Key Hierarchy
```typescript
// All keys follow same pattern
['exchange', 'listings', collectionAddress]
['exchange', 'listings', 'seller', sellerAddress]
['auction', 'details', auctionId]
['collection', 'info', address]
```

### 8.5 Better DevTools Experience
```typescript
// Keys are structured, readable in DevTools
exchange
  └─ listings
      ├─ collection: 0x123...
      └─ seller: 0xabc...
```

---

## 9. Potential Concerns & Mitigations

### 9.1 Breaking Changes
**Concern:** Public API might export query keys
**Mitigation:**
- Export old inline patterns as deprecated
- Add migration guide
- Keep query keys internal initially

### 9.2 Bundle Size
**Concern:** More code = larger bundle
**Mitigation:**
- Tree-shaking (ESM already enabled)
- Minimal overhead (~200 lines total)
- Cost justified by DX improvement

### 9.3 Learning Curve
**Concern:** New pattern for contributors
**Mitigation:**
- Document in code-standards.md
- Add examples to README
- Follow TanStack Query docs pattern

---

## 10. Recommended File Structure (Final)

```
src/react/
├── query-keys/
│   ├── index.ts                  # Barrel export
│   ├── exchange.query-keys.ts    # Exchange factory + options
│   ├── auction.query-keys.ts     # Auction factory + options
│   ├── collection.query-keys.ts  # Collection factory + options
│   └── types.ts                  # Shared types
├── hooks/
│   ├── useExchange.ts            # Refactored to use queryOptions
│   ├── useAuction.ts             # Refactored
│   └── useCollection.ts          # Refactored
└── index.ts                      # Export query keys for consumers
```

---

## 11. Comparison Table

| Aspect | Current (Inline) | Recommended (queryOptions) |
|--------|------------------|----------------------------|
| **Type Safety** | ❌ None | ✅ Full autocomplete |
| **Reusability** | ❌ Hook-only | ✅ Hook + prefetch + SSR |
| **Consistency** | ❌ Scattered patterns | ✅ Centralized factories |
| **Co-location** | ❌ Key separate from fn | ✅ Key + fn together |
| **Invalidation** | ❌ Inline strings | ✅ Type-safe factories |
| **Refactoring** | ❌ Manual search | ✅ Single source of truth |
| **Testing** | ❌ Hard to mock keys | ✅ Easy to import factories |
| **DevTools** | ⚠️ Inconsistent naming | ✅ Hierarchical, readable |
| **Bundle Size** | ✅ Minimal overhead | ✅ Tree-shakeable |
| **Learning Curve** | ✅ Simple strings | ⚠️ Requires understanding pattern |

---

## 12. Action Items

### Immediate (Next Sprint)
1. [ ] Create `src/react/query-keys/` directory structure
2. [ ] Implement `exchangeQueryKeys` factory
3. [ ] Create `listingsQueryOptions` following ZunoAPIClient pattern
4. [ ] Refactor `useExchange.ts` as proof-of-concept
5. [ ] Document decision in `docs/code-standards.md`

### Short Term (Sprint 2)
1. [ ] Complete Auction query keys + options
2. [ ] Complete Collection query keys + options
3. [ ] Refactor all hooks to use queryOptions
4. [ ] Update README with new pattern
5. [ ] Add migration guide

### Long Term
1. [ ] Consider auto-generating query keys from contract ABIs
2. [ ] Add query key linter (eslint-plugin-query-keys)
3. [ ] Export query keys for advanced consumers
4. [ ] Monitor for breaking changes in TanStack Query v6

---

## Unresolved Questions

1. **Should query keys be exported publicly?**
   - Current: Only `abiQueryKeys` exported
   - Decision: Keep internal initially, evaluate later

2. **How to handle dynamic query options (e.g., conditional queries)?**
   - Example: `enabled` depends on wallet state
   - Solution: Accept options override in hook

3. **Should we adopt a code generator?**
   - Tools: `@tanstack/query-core` has generators
   - Trade-off: More setup vs consistency

---

## Sources

- [TanStack Query v5 Query Options Guide](https://tanstack.com/query/v5/docs/react/guides/query-options)
- [Why queryOptions Will Change How You Use TanStack Query](https://medium.com/@jmytwenty8/why-queryoptions-will-change-how-you-use-tanstack-query-141608dd5c3c)
- [Building a Consistent Data Fetching Layer in React](https://ngandu.hashnode.dev/building-a-consistent-datafetching-layer-in-react-with-tanstack-query)
- [Mastering State Management with TanStack Query v5](https://dev.to/rajat128/from-beginner-to-pro-mastering-state-management-with-tanstack-query-v5-3hp6)

---

## Appendix: Complete Query Key Inventory

### Exchange Query Keys (Current)
```typescript
['listings', collectionAddress]
['listings', 'seller', seller]
['listing', listingId]
```

### Auction Query Keys (Current)
```typescript
['auction', auctionId]
['auctions']
['dutchAuctionPrice', auctionId]
['pendingRefund', auctionId, bidder]
```

### Collection Query Keys (Current)
```typescript
['collection', address]
['collections']
['createdCollections', creator, fromBlock, toBlock]
['userOwnedTokens', collectionAddress, userAddress]
['allowlist', collectionAddress, userAddress]
['allowlistOnly', collectionAddress]
['nfts']
['approvals', address]
```

### ABI Query Keys (Current - Using Factory ✅)
```typescript
['abs']
['abs', 'list']
['abs', 'detail', contractName, network]
['abs', 'detail', 'byId', abiId]
['contracts', address, network]
['networks']
```

---

**End of Report**
