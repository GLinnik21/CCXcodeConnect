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

The app registers as a login item and launches automatically at login.

## Uninstall

```bash
make uninstall
```

## Build from Source

```bash
xcodebuild -scheme XcodeIDEAdapter -configuration Release build
```

## CLI

The headless CLI can also be used directly:

```bash
swift run xcode-ide-adapter                    # supervisor mode (auto-manages all workspaces)
swift run xcode-ide-adapter --workspace /path  # single targeted workspace
```

## Usage

1. Install the app (`make install`)
2. Open one or more projects in Xcode — the adapter appears in the menu bar
3. In each Claude Code session, run `/ide` to connect to the matching workspace
4. Claude Code now has access to Xcode tools via the MCP server

Each Xcode window gets its own adapter instance with a dedicated WebSocket port and lock file. Multiple Claude Code clients can connect to the same workspace simultaneously.

## Architecture

The app registers as a login item via `SMAppService` and:

- Runs an `AdapterSupervisor` that monitors Xcode for open workspaces
- Creates one `AdapterServer` per workspace, each with its own WebSocket port and lock file
- Shares a single `xcrun mcpbridge` connection across all workspaces (routed by `tabIdentifier`)
- Polls for editor context (active file, selection) via AppleScript, filtered per workspace
- Supports multiple Claude Code clients per workspace (notifications broadcast, responses routed)
