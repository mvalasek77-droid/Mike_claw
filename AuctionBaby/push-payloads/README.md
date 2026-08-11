# Ready-to-send push payloads

Five `.apns` files, one per event type the client deep-links
(`PushService.Event`). Use them two ways.

## A. Simulator (no APNs, no server) — fastest
The `Simulator Target Bundle` key is already set to `com.valasek.auctionbaby`.

```sh
# Boot a sim and install the app first, then:
xcrun simctl push booted com.valasek.auctionbaby 1-bid.received.apns
xcrun simctl push booted com.valasek.auctionbaby 2-whisper.nodded.apns
xcrun simctl push booted com.valasek.auctionbaby 3-bid.accepted.apns
xcrun simctl push booted com.valasek.auctionbaby 4-message.received.apns
xcrun simctl push booted com.valasek.auctionbaby 5-match.dateDone.apns
```

Tap each banner → confirm it routes:
- `bid.received` / `whisper.nodded` → My Bids
- `bid.accepted` → the new match's chat
- `message.received` → that match's chat
- `match.dateDone` → the match / date-confirm

> Simulator note: the sim can show banners but does **not** have a real APNs
> token, so this exercises the **client routing** only, not the server→APNs
> leg. For that, use B on a real device.

## B. Real device via your own Worker (`POST /push/send`)
This is the true end-to-end path (Worker → APNs → device). The device must
have registered its token (sign in on the device first), and you need the
target user's `userId` and the `APP_SHARED_SECRET`.

```sh
AUTH=https://auctionbaby-auth.YOUR-SUBDOMAIN.workers.dev
SECRET=$APP_SHARED_SECRET          # same value you set with `wrangler secret put`
USER=<the-target-users-id>

curl -sS -X POST "$AUTH/push/send" \
  -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" \
  -d '{
        "userId": "'"$USER"'",
        "title": "SOLD! It'\''s a match",
        "body":  "Your bid was accepted. Open the chat and say hello.",
        "data":  { "type": "bid.accepted",
                   "bidId": "00000000-0000-0000-0000-0000000000b1",
                   "matchId": "00000000-0000-0000-0000-0000000000a7" }
      }'
```

Swap the `data.type` (and ids) for the other four events. The client reads
`type`, `bidId`, `matchId`, `messageId` whether they're top-level or nested
under `data`, so either shape works.

> The ids here are throwaway sentinels so the banner routes to the right tab.
> For `message.received` / `bid.accepted` to open a **specific** live chat, use
> a real `matchId` from that device's account.
