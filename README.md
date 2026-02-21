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

## Install

```bash
make install
```

After first install, enable the extension:

1. Open **System Settings > General > Login Items & Extensions > Xcode Source Editor**
2. Enable **XcodeIDEAdapter**
3. Restart Xcode

The adapter will launch automatically whenever Xcode starts.

## Uninstall

```bash
make uninstall
```

## Build from Source

```bash
# Using Xcode project
xcodebuild -scheme XcodeIDEAdapter -configuration Release build

# Using Swift Package Manager (adapter only, no extension)
swift build -c release
```

## Usage

1. Install the app and enable the extension (see above)
2. Open a project in Xcode — the adapter starts automatically and appears in the menu bar
3. In Claude Code, run `/ide` to connect
4. Claude Code now has access to Xcode tools via the MCP server

The adapter automatically detects when you switch projects in Xcode and updates the connection.

## Architecture

The app includes a Source Editor Extension that triggers the host app via a custom URL scheme (`xcode-ide-adapter://activate`) when Xcode launches. The host app then:

- Starts a WebSocket MCP server on a random port (127.0.0.1)
- Writes a lock file to `~/.claude/ide/{port}.lock` for Claude Code discovery
- Spawns `xcrun mcpbridge` to access Xcode's 20 built-in tools
- Polls for editor context (active file, selection) via AppleScript
