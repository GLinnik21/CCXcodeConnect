---
paths:
  - "Sources/XcodeConnectCore/MCPToolRouter.swift"
  - "Sources/XcodeConnectCore/Tools/**"
---

# Tool Routing

`MCPToolRouter` exposes 10 IDE-specific tools that conform to the IDE API:

| IDE Tool | Implementation |
|----------|---------------|
| `openFile` | `xed --line N path`; supports `startText` for text-based line navigation |
| `getDiagnostics` | Proxies to `XcodeListNavigatorIssues`; accepts both `filePath` and `uri` (`file:///path`) via `resolveFilePath()` |
| `executeCode` | Proxies to `ExecuteSnippet` via mcpbridge |
| `getCurrentSelection` / `getLatestSelection` | Returns current editor selection from `EditorContext` |
| `getOpenEditors` | Lists open editors via AppleScript |
| `getWorkspaceFolders` | Returns detected workspace paths |
| `checkDocumentDirty` | Checks unsaved changes via AppleScript |
| `saveDocument` | Saves a document via AppleScript |
| `closeAllDiffTabs` | No-op (returns OK); Xcode has no diff tabs like VS Code |

Only `getDiagnostics` and `executeCode` are exposed to the LLM by Claude Code. All other tools are called internally by Claude Code itself — never by the model.

Only `getDiagnostics` and `executeCode` proxy to mcpbridge internally; other Xcode MCP bridge tools are not exposed. Unknown tool calls return an error.
