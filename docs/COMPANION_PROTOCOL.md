# CodeGenie Terminal Runner Protocol

Lightweight local-network bridge between the iOS app and a Terminal
process running on the user's Mac. The phone tells the Mac to open Xcode,
open Safari, build the app, or capture a screenshot while the user stays
in the iPhone UI.

There is no packaged companion Mac app in this branch. The Mac-side
process is started from Terminal:

```sh
cd mac_terminal_runner
swift run codegenie-terminal-runner
```

## Threat Model

- **Local network only.** The runner listens on the user's Mac and is
  meant for the same Wi-Fi network.
- **Pairing is mandatory.** Terminal prints a `codegenie://pair?...`
  URL carrying `(host, port, token)`. The iOS client stores the token in
  Keychain and sends it in the first `auth` request.
- **Allow-listed actions only.** The runner refuses commands outside
  this schema. There is no generic "run shell" command.
- **User-confirmed escalation.** Anything that types, clicks, fills App
  Store Connect, or moves through Apple account gates must be confirmed
  by the user.

## Discovery

The runner advertises Bonjour service `_codegenie-runner._tcp` so the
iOS app can find it on the same Wi-Fi network. The user can also paste
the pairing URL printed in Terminal.

## Transport

TCP, newline-delimited JSON. Exactly one JSON envelope per line. The
runner may send event envelopes for long-running commands.

## Message Envelope

```json
{
  "v": 1,
  "id": "msg_<random>",
  "kind": "request|response|event",
  "type": "open_xcode_project",
  "payload": {},
  "in_response_to": "msg_<id>",
  "ok": true,
  "error": null
}
```

Requests get a single `response`. Long-running operations send
intermediate `event` frames, such as `xcodebuild.line`, referencing the
original request id via `in_response_to`.

## Commands

### `ping`

Returns `{ "pong": true }`.

### `open_xcode_project`

```json
{ "path": "/Users/example/code/app/App.xcodeproj" }
```

### `open_safari`

```json
{ "url": "https://appstoreconnect.apple.com/apps", "new_window": true }
```

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

Streams `xcodebuild.line` events and finishes with `{ "exit_code": 0,
"log_tail": "..." }`.

### `screenshot`

```json
{ "display": 0 }
```

Returns `{ "image_b64": "..." }`.

### `app_store_connect.fill`

```json
{ "field": "app_name", "value": "TideRider" }
```

Drives the Safari window with AppleScript/JavaScript only after user
confirmation on the Mac.

## Events

- `xcodebuild.line` — `{ "line": "..." }`
- `xcodebuild.diagnostic` — `{ "file": "...", "line": 42, "severity": "error", "message": "..." }`
- `runner.shutting_down` — graceful shutdown, client should reconnect
- `auth.revoked` — token revoked, client should re-pair

## Implementation Notes

- `mac_terminal_runner/` is intentionally a Swift CLI package, not a Mac app.
- iOS stores paired tokens in Keychain so it can reconnect on launch.
- Keep payload structs Codable and keep the JSON examples above as test fixtures.
