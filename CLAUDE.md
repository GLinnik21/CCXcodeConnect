# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                                                        # build library + CLI
swift run xcode-ide-adapter                                        # run CLI (headless)
xcodebuild -scheme XcodeIDEAdapter -configuration Release build    # build .app
make install                                                       # build + install .app to ~/Applications
make uninstall                                                     # remove app + lock files
```

Requires macOS 14+ and a running Xcode instance with `xcrun mcpbridge` available (Xcode 26.3+).

The .app registers as a login item via `SMAppService.mainApp` so it starts automatically at login.

## Architecture

This repo has three targets managed via a `Package.swift` at the repo root:

- **IDEAdapterCore** (library) — all core logic in `Sources/IDEAdapterCore/`
- **xcode-ide-adapter** (CLI executable) — thin entry point in `Sources/xcode-ide-adapter/`
- **XcodeIDEAdapter.app** (Xcode project) — thin menu bar wrapper in `XcodeIDEAdapter/`, references the local package

```
Claude Code CLI ──WebSocket (MCP)──> AdapterServer (IDEAdapterCore)
                                        ├── xcrun mcpbridge (STDIO JSON-RPC, 20 tools)
                                        └── AppleScript → Xcode (selection, active file)
```

**AdapterServer** (`Sources/IDEAdapterCore/AdapterServer.swift`) orchestrates everything:
- Starts `WebSocketServer` on a random port bound to 127.0.0.1
- Writes a lock file to `~/.claude/ide/{port}.lock` so Claude Code discovers it
- Monitors Xcode via `XcodeMonitor` (NSWorkspace notifications)
- When Xcode launches: spawns `MCPBridgeClient` → `xcrun mcpbridge`, detects workspaces, starts `EditorContext` polling
- When Xcode quits: tears down bridge and polling
- Exposes `onStateChange` callback for UI or CLI status updates

**Request flow**: WebSocket frame → `WebSocketServer.handleMessage` → JSON-RPC decode → `MCPToolRouter.callTool` → either local IDE tool handler or proxy to mcpbridge.

**Editor context**: `EditorContext` polls Xcode every 500ms via AppleScript (`osascript`) for active file path and selection range, sends `selection_changed` JSON-RPC notifications over WebSocket.

## Key Implementation Details

- **NIO WebSocket handlers** must be created per-connection in `upgradePipelineHandler` (not shared). Use `handlerAdded` (not `channelActive`) to register the client channel since the channel is already active during HTTP→WS upgrade.
- **Channel writes** (`writeAndFlush`) must happen on the NIO event loop via `channel.eventLoop.execute {}`.
- **MCPBridgeClient** uses `NSLock.withLock` for thread-safe request tracking and `CheckedContinuation` to bridge callback-based STDIO I/O to async/await.
- **mcpbridge response format**: Tool results come as `content[].text` containing JSON with a `message` field (e.g. `{"message":"* tabIdentifier: X, workspacePath: Y"}`), not as structured JSON arrays.
- **Lock file cleanup**: `LockFileManager` removes stale `.lock` files from crashed instances on startup by checking PIDs with `kill(pid, 0)`.

## Tool Routing

`MCPToolRouter` exposes 5 IDE-specific tools + all 20 mcpbridge tools:

| IDE Tool | Implementation |
|----------|---------------|
| `openDiff` | No-op, returns FILE_SAVED (CLI handles diffs) |
| `closeDiff` / `closeAllDiffTabs` | No-op, returns CLOSED |
| `openFile` | `xed --line N path` |
| `getDiagnostics` | Proxies to `XcodeListNavigatorIssues` with optional glob filter by file |

All other tool calls are proxied to mcpbridge with `tabIdentifier` auto-injected.
