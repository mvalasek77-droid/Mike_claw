# Web Push (VAPID) — server contract

The **client is fully wired**: the service worker shows notifications
(`push` + `notificationclick` in `sw.js`), and `API.enableWebPush()` requests
permission, subscribes via the browser's `PushManager`, and POSTs the
subscription to the auth Worker. **Two server pieces remain** — storing
subscriptions and sending encrypted pushes.

## 1. Generate VAPID keys (once)
```sh
npx web-push generate-vapid-keys
# → Public Key  (put in web/config.js → VAPID_PUBLIC_KEY)
# → Private Key (auth Worker secret: wrangler secret put VAPID_PRIVATE_KEY)
```
Also set a `VAPID_SUBJECT` (a `mailto:` or your site URL) as a Worker var.

## 2. Store subscriptions — `POST /devices/register-web`  [auth]
The client already calls this with:
```json
{ "subscription": { "endpoint": "...", "keys": { "p256dh": "...", "auth": "..." } } }
```
Worker: resolve the userId from the session (same as `/devices/register`), then
persist the subscription JSON (D1 row or KV keyed by userId, allowing several
per user). Idempotent on `endpoint`.

## 3. Send a push
Add a `sendWebPush(userId, { title, body, url })` that, for each stored
subscription, performs the standard **Web Push** flow:
- **VAPID auth header**: an ES256 JWT signed with `VAPID_PRIVATE_KEY`
  (`{ aud: <origin of endpoint>, exp: now+12h, sub: VAPID_SUBJECT }`), sent as
  `Authorization: vapid t=<jwt>, k=<VAPID_PUBLIC_KEY>`.
- **Payload encryption**: `aes128gcm` per RFC 8291 (ECDH with the sub's
  `p256dh`, HKDF with the `auth` secret → CEK + nonce, AES-GCM the JSON body).
- `POST` to `subscription.endpoint` with headers `TTL`, `Content-Encoding: aes128gcm`.
- On `404`/`410`, delete that subscription (it's expired).

Reuse the existing ES256 signing already in the auth Worker (it signs APNs
JWTs). The one new bit is the aes128gcm content encryption — port a small,
audited implementation (e.g. the algorithm from the `web-push` library) into the
Worker's WebCrypto.

## 4. Fan-in from the other Workers
Wherever the matching Worker notifies today (bid received, accepted, message),
have it call the auth Worker's web-push send in addition to APNs — same event
payload (`{ type, matchId, ... }`) so `sw.js` deep-links via the `url`/`hash`.

## Client recap (already done)
- `config.js` → `VAPID_PUBLIC_KEY`
- `api.js` → `enableWebPush()` (permission → subscribe → register)
- `sw.js` → `push` shows the notification, `notificationclick` focuses/opens the app
- `app.js` → **You → Enable notifications** button (shown when configured + signed in)
