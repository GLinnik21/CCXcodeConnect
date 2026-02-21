# Xcode IDE Adapter

A macOS menu bar app that connects [Claude Code](https://claude.ai/code) to Xcode via the `/ide` integration.

It bridges Claude Code's WebSocket MCP protocol to Xcode's `xcrun mcpbridge` STDIO MCP server, giving Claude Code full access to Xcode's project tools and editor context.

## What It Does

When running, Claude Code can:

- **Read and navigate** Xcode project structure (files, directories, search)
- **Edit files** directly in the Xcode project
- **Build the project** and retrieve build logs and errors
- **Get diagnostics** (errors, warnings) from the Issue Navigator
- **Run tests** (all or specific) from the active test plan
- **Open files** in Xcode at specific line numbers
- **Execute Swift snippets** in the context of project source files
- **Render SwiftUI previews** and return snapshots
- **Track editor context** (active file, cursor position, selection) in real time

## Requirements

- macOS 14+
- Xcode 26.3+ (for `xcrun mcpbridge` support)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## Build & Run

```bash
swift build -c release
swift run &
```

The app appears in the menu bar and automatically connects when Xcode is running. Claude Code discovers it via a lock file at `~/.claude/ide/{port}.lock`.

## Usage

1. Launch the adapter (it sits in the menu bar)
2. Open a project in Xcode
3. In Claude Code, run `/ide` to connect
4. Claude Code now has access to Xcode tools via the MCP server

The adapter automatically detects when you switch projects in Xcode and updates the connection.
