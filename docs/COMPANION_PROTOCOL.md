# CodeGenie Companion Protocol

Lightweight WebSocket bridge between the iOS app and a daemon running on
the user's Mac. The phone tells the Mac to "open Xcode at this path",
"open Safari at App Store Connect step 3", "build the app", "screenshot
this URL" — keeping the user in the iPhone UI but reaching into the
Mac when the task needs Xcode, Safari, or a real keyboard.

## Threat model & guarantees

- **Local network only.** The companion binds to `127.0.0.1` plus the
  device's link-local IPv6 address. Nothing is exposed to the internet.
- **Pairing is mandatory.** A short-lived QR code shown by the daemon
  carries `(host, port, token)` — the iOS client stores the token in
  Keychain. Every subsequent connection presents the token in the
  WebSocket subprotocol header.
- **Tokens are revocable.** The daemon's tray icon has "Revoke all
  tokens" → instantly rotates the secret and disconnects everyone.
- **Allow-listed actions only.** The daemon refuses any command not in
  the schema below. There is no generic "run shell" command — the
  swarm uses its own sandboxed runner for that.
- **User-confirmed escalation.** Anything that types keystrokes,
  presses keys, or moves the mouse triggers a banner the user has to
  approve in real time.

## Discovery

The daemon advertises Bonjour service `_codegenie-companion._tcp` so the
iOS app can find it on the same Wi-Fi network. iOS shows a list of
candidates; user picks one and scans the QR code.

## Transport

WebSocket, JSON message frames. Exactly one message per frame — no
batching. Both sides may send unsolicited events.

## Message envelope

```json
{
  "v": 1,
  "id": "msg_<random>",
  "kind": "request|response|event",
  "type": "open_xcode_project",
  "payload": { ... },
  "in_response_to": "msg_<id>",
  "ok": true,
  "error": null
}
```

- Requests get a single `response`. Long-running operations send
  intermediate `event` frames (e.g. `xcodebuild.line`) referencing the
  original request id via `in_response_to`.
- Errors set `ok: false` and put a human-readable string in `error`.

## Commands

### `ping` → `pong`
Health check. Round-trip latency budget.

### `open_xcode_project`
```json
{ "path": "/Users/clawcl/code/codegenie/ios/CodeGenie.xcodeproj" }
```
Opens the project in Xcode. Returns `{ "pid": 1234 }`.

### `open_safari`
```json
{ "url": "https://appstoreconnect.apple.com/apps", "new_window": true }
```
Opens Safari. Returns nothing.

### `xcodebuild`
```json
{
  "action": "build|test|archive",
  "scheme": "CodeGenie",
  "destination": "platform=iOS Simulator,name=iPhone 16",
  "workspace_or_project": "/path/to/Project.xcodeproj",
  "configuration": "Debug"
}
```
Streams `xcodebuild.line` events as the build progresses, finishes with
a `response` carrying `{ ok, exit_code, log_tail }`.

### `screenshot`
```json
{ "display": 0 }
```
Captures a PNG of display 0, returns `{ "image_b64": "..." }`.

### `app_store_connect.fill`
```json
{ "field": "app_name", "value": "TideRider" }
```
Drives the Safari window with AppleScript / accessibility APIs. **Asks
the user for confirmation on the Mac before each fill.** The phone shows
a "press confirm on your Mac" prompt while waiting.

### `revoke_token`
Daemon-side only — fired by the menu bar action. Closes every active
connection.

## Events the daemon may emit

- `xcodebuild.line` — `{ "line": "..." }`
- `xcodebuild.diagnostic` — `{ "file": "...", "line": 42, "severity": "error", "message": "..." }`
- `daemon.shutting_down` — graceful shutdown, client should reconnect
- `auth.revoked` — token revoked, client should re-pair

## Versioning

Protocol version on every envelope (`"v": 1`). Daemon refuses
connections with a higher version it doesn't understand and replies
with a `version_mismatch` close frame.

## Implementation notes

- The Python prototype daemon (`mac_companion_py/`) is a starter that
  Hermes can use today. The native Swift Package (`mac_companion/`) is
  the production target — it ships a menu bar icon, sandboxed
  AppleScript bridge, and signed binary distribution.
- Both must implement the same wire format. The reference encoding
  fixtures live in `mac_companion/tests/fixtures/`.
