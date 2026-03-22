# CLAUDE.md

## Build & Run

```bash
swift build                                                        # build library + CLI
swift run cc-xcode-connect                                         # run CLI (headless)
xcodebuild -scheme CCXcodeConnect -configuration Release build     # build .app
make install                                                       # build + install .app to ~/Applications
make uninstall                                                     # remove app + lock files
```

Requires macOS 14+ and a running Xcode instance with `xcrun mcpbridge` available (Xcode 26.3+).

```bash
LOG_LEVEL=debug swift run cc-xcode-connect                         # run with debug logging
```

The .app registers as a login item via `SMAppService.mainApp` so it starts automatically at login.

## App Architecture
- Pure AppKit (no SwiftUI) — NSStatusItem + NSMenu for menu bar, NSWindow for settings
- LSUIElement=true in Info.plist (no Dock icon)
- Settings stored in UserDefaults via injectable `AdapterSettingsProviding` protocol
- Polling settings apply live via `restartPolling()` chain: AppDelegate → AdapterSupervisor → AdapterServer → EditorContext

## Protocol Constraints
- Server name MUST be `"ide"` — Claude Code searches `mcpClients` for `name === "ide"`
- Lock file: `~/.claude/ide/{port}.lock` with `{pid, workspaceFolders, ideName, transport:"ws", runningInWindows, authToken}`
- Auth header: `X-Claude-Code-Ide-Authorization: {uuid}`, rejected with close code 1008 if invalid
- `getDiagnostics` severity is a STRING ("Error", "Warning", "Info", "Hint"), NOT an integer
- Lines are 0-indexed in the protocol (Xcode returns 1-indexed, subtract 1)
- `getDiagnostics` URI filter: use `**/filename.swift` glob (full path causes mcpbridge double-slash bug)
- XcodeListNavigatorIssues: pass `severity: "remark"` to get all issues (default is "error" only)

## Gotchas

- **NIO WebSocket handlers** must be created per-connection in `upgradePipelineHandler` (not shared). Use `handlerAdded` (not `channelActive`) to register the client channel since the channel is already active during HTTP→WS upgrade.
- **Channel writes** (`writeAndFlush`) must happen on the NIO event loop via `channel.eventLoop.execute {}`.
- **MCPBridgeClient** uses `NSLock.withLock` for thread-safe request tracking and `CheckedContinuation` to bridge callback-based STDIO I/O to async/await.
- **mcpbridge response format**: Tool results come as `content[].text` containing JSON with a `message` field (e.g. `{"message":"* tabIdentifier: X, workspacePath: Y"}`), not as structured JSON arrays.
- **Lock file cleanup**: `LockFileManager` removes stale `.lock` files from crashed instances on startup by checking PIDs with `kill(pid, 0)`.
