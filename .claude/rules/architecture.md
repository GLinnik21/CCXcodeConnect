---
paths:
  - "Sources/XcodeConnectCore/**"
  - "Sources/cc-xcode-connect/**"
  - "CCXcodeConnect/**"
---

# Architecture

Three targets managed via `Package.swift`:

- **XcodeConnectCore** (library) — all core logic in `Sources/XcodeConnectCore/`
- **cc-xcode-connect** (CLI executable) — thin entry point in `Sources/cc-xcode-connect/`
- **CCXcodeConnect.app** (Xcode project) — thin menu bar wrapper in `CCXcodeConnect/`, references the local package

## Multi-Workspace Support

`AdapterSupervisor` monitors Xcode and creates one `AdapterServer` per open workspace, each with its own WebSocket port, lock file, and editor context — but all sharing a single `MCPBridgeClient` connection to `xcrun mcpbridge`.

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

**Request flow**: WebSocket frame → `WebSocketServer.handleMessage` → JSON-RPC decode → `MCPToolRouter.callTool` → local IDE tool handler (some tools internally proxy to mcpbridge with per-workspace `tabIdentifier`).

**Editor context**: `EditorContext` polls Xcode every 500ms via AppleScript (`osascript`) for active file path and selection range, sends `selection_changed` JSON-RPC notifications over WebSocket. Each worker filters events by its `workspaceFilter` path prefix.
