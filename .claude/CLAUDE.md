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

The .app registers as a login item via `SMAppService.mainApp` so it starts automatically at login.

## Gotchas

- **NIO WebSocket handlers** must be created per-connection in `upgradePipelineHandler` (not shared). Use `handlerAdded` (not `channelActive`) to register the client channel since the channel is already active during HTTP→WS upgrade.
- **Channel writes** (`writeAndFlush`) must happen on the NIO event loop via `channel.eventLoop.execute {}`.
- **MCPBridgeClient** uses `NSLock.withLock` for thread-safe request tracking and `CheckedContinuation` to bridge callback-based STDIO I/O to async/await.
- **mcpbridge response format**: Tool results come as `content[].text` containing JSON with a `message` field (e.g. `{"message":"* tabIdentifier: X, workspacePath: Y"}`), not as structured JSON arrays.
- **Lock file cleanup**: `LockFileManager` removes stale `.lock` files from crashed instances on startup by checking PIDs with `kill(pid, 0)`.
