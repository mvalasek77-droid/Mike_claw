# CodeGenie Companion Protocol

An encrypted link between the iOS app and a daemon running on the
user's Mac. The phone tells the Mac to "open Xcode at this path",
"open Safari at App Store Connect", "archive and upload this app" —
keeping the user in the iPhone UI but reaching into the Mac when the
task needs Xcode, Safari, or a signing identity.

## Threat model & guarantees

- **Local network only.** The companion listens on the Mac's local
  network interfaces. Nothing is exposed to the internet.
- **Encrypted and pinned.** The connection is TLS 1.2 or later. The
  companion creates a self-signed certificate on first launch and puts
  its SHA-256 fingerprint in the pairing code. The phone accepts a
  certificate with that fingerprint and no other, so another device on
  the same Wi-Fi cannot impersonate the Mac. This matters because the
  App Store Connect signing key crosses this link during an upload.
- **Pairing is mandatory.** The code shown by the daemon carries
  `(host, port, token, fp)`. The phone stores it in the Keychain and
  presents the token in the first message of every connection.
- **Allow-listed actions only.** The daemon refuses any command not in
  the schema below. There is no generic "run shell" command.
- **User-confirmed escalation.** Anything that types into a page
  triggers a dialog on the Mac the user has to approve.

## Pairing code

```
codegenie://pair?host=<name>.local&port=<port>&token=<token>&fp=<sha256 hex>
```

Shown as a QR code and as a link. A code without `fp` comes from a
companion that predates encrypted pairing and is refused by the app.

## Discovery

The daemon advertises Bonjour service `_codegenie-companion._tcp`. The
app uses this only to show that a companion is running nearby. It never
connects from an advertisement: an advertisement carries no token and
no fingerprint.

## Transport

TLS, carrying newline-delimited JSON: one message per line. Both sides
may send unsolicited events. The first message must be `auth`.

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

### `workspace.fetch`
```json
{
  "job_id": "job_abc123",
  "export_url": "https://api.example/api/coding/swarm/job_abc123/export",
  "token": "<backend token>"
}
```
Downloads the generated app's workspace zip from the build server and
unpacks it under `~/Library/Application Support/CodeGenie/workspaces/
<job_id>`. Signing has to happen where Xcode is, and Xcode needs the
actual files. Streams `workspace.fetch.line` events; returns
`{ ok, workspace_root }` pointing at the folder that holds the project.

`job_id` is used as a directory name and is rejected if it contains a
path separator or `..`.

### `xcodebuild.archive_export`
```json
{
  "workspace_root": "/Users/you/Library/.../job_abc123",
  "team_id": "ABCD123456",
  "scheme": "",
  "workspace_or_project": "",
  "configuration": "Release",
  "export_method": "app-store-connect",
  "asc_api_key_id": "ABCDEFGH12",
  "asc_api_issuer_id": "0000-...",
  "asc_api_key_pem": "-----BEGIN PRIVATE KEY-----\n..."
}
```
Archives and exports a signed `.ipa` with automatic signing
(`-allowProvisioningUpdates`). Blank `scheme` / `workspace_or_project`
means "detect it here" — only this machine can see what the generated
project actually is. Streams `xcodebuild.line` events; returns
`{ ok, ipa_path, absolute_path, scheme, project }`, or
`{ ok: false, phase, exit_code, log_tail }`.

### `asc.upload`
```json
{
  "ipa_path": "/Users/you/.../build/export/App.ipa",
  "asc_api_key_id": "ABCDEFGH12",
  "asc_api_issuer_id": "0000-...",
  "asc_api_key_pem": "-----BEGIN PRIVATE KEY-----\n..."
}
```
Runs `altool --validate-app` then `--upload-app`. Validating first is
deliberate: most rejections surface in seconds, and finding them before
a multi-minute upload saves that wait. Streams `asc.upload.line`
events; returns `{ ok, phase, exit_code, log_tail, detail }`.

Falls back to `apple_id` + `app_specific_password` when no API key is
supplied.

#### Handling of `asc_api_key_pem`

The App Store Connect signing key lives in the phone's Keychain and is
never sent to CodeGenie's servers. Both commands above accept it inline
for the duration of one command: the daemon writes it to a `0600` file
inside a `0700` temporary directory, passes that path to `xcodebuild` /
`altool` (neither accepts a key any other way), and deletes it on every
exit path including thrown errors. It is never logged and never written
to the workspace.

`asc_api_key_path` remains supported for a key already on the Mac.

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

- `xcodebuild.line` — `{ "line": "...", "phase": "archive|export|..." }`
- `xcodebuild.diagnostic` — `{ "file": "...", "line": 42, "severity": "error", "message": "..." }`
- `asc.upload.line` — `{ "line": "...", "phase": "validate|upload" }`
- `workspace.fetch.line` — `{ "line": "...", "phase": "download|unpack" }`
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
