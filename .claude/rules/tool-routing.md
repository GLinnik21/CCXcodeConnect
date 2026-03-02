---
paths:
  - "Sources/XcodeConnectCore/MCPToolRouter.swift"
  - "Sources/XcodeConnectCore/Tools/**"
---

# Tool Routing

`MCPToolRouter` exposes 9 IDE-specific tools that conform to the IDE API:

| IDE Tool | Implementation |
|----------|---------------|
| `openFile` | `xed --line N path` |
| `getDiagnostics` | Proxies to `XcodeListNavigatorIssues` with optional glob filter by file |
| `executeCode` | Proxies to `ExecuteSnippet` via mcpbridge |
| `getCurrentSelection` / `getLatestSelection` | Returns current editor selection from `EditorContext` |
| `getOpenEditors` | Lists open editors via AppleScript |
| `getWorkspaceFolders` | Returns detected workspace paths |
| `checkDocumentDirty` | Checks unsaved changes via AppleScript |
| `saveDocument` | Saves a document via AppleScript |

Diff tools (`openDiff`, `closeDiff`, `closeAllDiffTabs`) are intentionally not exposed — Claude Code falls back to its built-in terminal diff view, which gives the user proper accept/reject control.

Only `getDiagnostics` and `executeCode` proxy to mcpbridge internally; other Xcode MCP bridge tools are not exposed. Unknown tool calls return an error.
