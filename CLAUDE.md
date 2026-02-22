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

### Multi-Workspace Support

The adapter supports N simultaneous Xcode windows. An `AdapterSupervisor` monitors Xcode and creates one `AdapterServer` per open workspace, each with its own WebSocket port, lock file, and editor context — but all sharing a single `MCPBridgeClient` connection to `xcrun mcpbridge`.

```
AdapterSupervisor (XcodeMonitor + workspace polling)
  ├── MCPBridgeClient → xcrun mcpbridge (shared, 1 process)
  ├── AdapterServer(workspace: "/Users/x/ProjectA")
  │     ├── WebSocketServer :54321 → Claude Code #1, #2, ...
  │     ├── LockFile ~/.claude/ide/54321.lock
  │     ├── MCPToolRouter (tabIdentifier=windowtab1)
  │     └── EditorContext (filters files under /Users/x/ProjectA)
  └── AdapterServer(workspace: "/Users/x/ProjectB")
        ├── WebSocketServer :54322 → Claude Code #3
        ├── LockFile ~/.claude/ide/54322.lock
        ├── MCPToolRouter (tabIdentifier=windowtab2)
        └── EditorContext (filters files under /Users/x/ProjectB)
```

Each WebSocket server accepts multiple Claude Code clients simultaneously — notifications are broadcast to all, responses are routed back to the sender.

The CLI also supports `--workspace <path>` for running a single targeted instance with its own bridge client.

**Request flow**: WebSocket frame → `WebSocketServer.handleMessage` → JSON-RPC decode → `MCPToolRouter.callTool` → either local IDE tool handler or proxy to mcpbridge (with per-workspace `tabIdentifier`).

**Editor context**: `EditorContext` polls Xcode every 500ms via AppleScript (`osascript`) for active file path and selection range, sends `selection_changed` JSON-RPC notifications over WebSocket. Each worker filters events by its `workspaceFilter` path prefix.

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
