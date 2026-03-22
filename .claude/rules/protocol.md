---
paths:
  - "Sources/XcodeConnectCore/WebSocketServer.swift"
  - "Sources/XcodeConnectCore/MCPRequestHandler.swift"
  - "Sources/XcodeConnectCore/AdapterServer.swift"
  - "Sources/XcodeConnectCore/EditorContext.swift"
  - "Sources/XcodeConnectCore/LockFileManager.swift"
  - "Sources/XcodeConnectCore/Tools/GetDiagnosticsTool.swift"
---

# Claude Code IDE Protocol

Reverse-engineered from Claude Code CLI and VS Code extension.

## getDiagnostics Response Format (LSP)
```json
[
  {
    "uri": "file:///absolute/path/to/File.swift",
    "linesInFile": 120,
    "diagnostics": [
      {
        "message": "error text",
        "severity": "Error",
        "range": {
          "start": {"line": 3, "character": 0},
          "end": {"line": 3, "character": 0}
        },
        "source": "Xcode",
        "code": "optional"
      }
    ]
  }
]
```
Severity mapping: Xcode "error"→"Error", "warning"→"Warning", "remark"→"Info".

## openDiff Sentinel Responses
Claude Code BLOCKS waiting for one of: `"FILE_SAVED"` (+ content), `"TAB_CLOSED"`, `"DIFF_REJECTED"`. We return "Unknown tool" error to fall back to terminal diff.

## Notifications (IDE → Claude Code)

### selection_changed
```json
{"jsonrpc":"2.0","method":"selection_changed","params":{"text":"","filePath":"/path","fileUrl":"file:///path","selection":{"start":{"line":0,"character":0},"end":{"line":5,"character":10},"isEmpty":false}}}
```

### diagnostics_changed
```json
{"jsonrpc":"2.0","method":"diagnostics_changed","params":{"uris":["file:///path/to/File.swift"]}}
```
Claude Code 2.1.63 does NOT handle this (harmless). Disabled by default in settings.

## Notifications (Claude Code → IDE)

### ide_connected
```json
{"jsonrpc":"2.0","method":"ide_connected","params":{"pid":12345}}
```
Sent after WebSocket connection. We store the PID in `state.connectedPID`.

## VS Code Extension Response Formats (for compatibility)
- `getOpenEditors`: `{tabs: [{uri, path, label, isActive, isDirty}]}`
- `getWorkspaceFolders`: `{success, folders: [{name, uri, path, index}], rootPath, workspaceFile}`
- `getCurrentSelection`: `{success, text, filePath, fileUrl, selection: {start, end, isEmpty}}`
- `closeAllDiffTabs`: `"CLOSED_N_DIFF_TABS"` (response not checked)
