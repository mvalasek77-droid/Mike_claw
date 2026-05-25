# AI Marketplace — backend contract

The iOS app currently runs **client-only** with on-device encrypted storage.
`openapi.yaml` is the contract for the production backend it should talk to —
the P0 foundation from `../AUDIT.md`. Nothing here is deployed yet; it's the
spec a backend team (or Codex) implements against.

## Suggested architecture

```
iOS app ──HTTPS──▶ API Gateway ──▶ services
                                   ├─ Auth        (Sign in with Apple token exchange, JWT sessions)
                                   ├─ Account     (profile, GDPR/5.1.1 delete)
                                   ├─ Catalog     (Postgres + search index: Algolia/Elasticsearch)
                                   ├─ Media       (signed uploads → S3/GCS → transcode → HLS on CDN)
                                   ├─ Submissions (AI Editor review jobs, moderation)
                                   ├─ Commerce    (StoreKit receipt validation, wallet ledger, entitlements)
                                   ├─ Payouts     (Stripe Connect / Apple, KYC, tax forms)
                                   └─ Ledger      (NRN: consensus node + explorer)
```

## How the current client maps to it

| App today (client-only) | Production endpoint |
|---|---|
| `SampleData` + `ContentFoundry` seed catalogue | `GET /catalog`, `GET /catalog/{id}` |
| `MarketplaceStore.search` | `GET /catalog/search` |
| `AIEditor.review` (on-device heuristic) | `POST /submissions` → `GET /submissions/{id}/review` (server model) |
| `PhotosPicker` cover + bundled samples | `POST /media/upload-url` → `GET /media/{assetID}/status` |
| `StoreKitService` (on-device verification) | `POST /commerce/validate-receipt` (server JWS verification) |
| `MarketplaceStore` wallet + `libraryIDs` | `POST /commerce/purchase`, `GET /library` |
| `CreatorDashboardView` | `GET /payouts` |
| `AICoinLedger` (on-device chain) | `GET /ledger/blocks`, `GET /ledger/agents/{name}` |
| Sign in with Apple (`RegisterView`) | `POST /auth/apple` |
| `MarketplaceStore.deleteAccount()` | `DELETE /account` |

## Key compliance note — receipt validation

StoreKit 2 already verifies a transaction's JWS signature **on-device**
(`VerificationResult.verified`). For production, the client should also send
`Transaction.jwsRepresentation` to `POST /commerce/validate-receipt` so the
**server** verifies against Apple's root certs, guards against replay, and is
the source of truth for wallet credit. That server step is specced here but not
yet implemented.
