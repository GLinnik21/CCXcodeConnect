# CC Xcode Connect

A macOS menu bar app that connects Xcode to [Claude Code](https://claude.ai/code), so Claude can see your open files, cursor position, and build diagnostics as you work.

<img src="assets/status_bar.png" width="400" alt="CC Xcode Connect menu bar dropdown">

In Claude Code:

<img src="assets/ide-select.png" width="800" alt="Select Xcode workspace in /ide">
<img src="assets/ide-in-readme.png" width="800" alt="Claude Code sees your active file">
<img src="assets/ide-11-lines.png" width="800" alt="Claude Code sees selected lines">
<img src="assets/ide-diagnostics.jpeg" width="800" alt="Claude Code found diagnostic issues">

## Requirements

- macOS 14+
- Xcode 26.3+ (for `xcrun mcpbridge` support)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## Install

### Homebrew (recommended)

```bash
brew install --cask GLinnik21/tap/cc-xcode-connect
```

On first launch, macOS will block it because the app is not notarized. Go to **System Settings > Privacy & Security** and click **Open Anyway**.

### Download

Grab the latest `.zip` from [Releases](https://github.com/GLinnik21/CCXcodeConnect/releases), extract, and move to `~/Applications` (or `/Applications`). On first launch, go to **System Settings > Privacy & Security** and click **Open Anyway**.

### Build from source

```bash
make install
```

The app starts automatically at login — no need to launch it manually after the first time.

## Usage

1. Open one or more projects in Xcode — the menu bar icon indicates the connection is established
2. When Xcode asks to allow CC Xcode Connect to access Xcode, click **Allow**
3. In Claude Code, run `/ide` to connect to the matching workspace
4. Claude Code can now see your active file, cursor position, and diagnostics

You can enable auto-connect in `/config` or by launching Claude Code with `--ide`.

Each Xcode workspace gets its own connection. Multiple Claude Code sessions can connect to the same workspace simultaneously.

## Tips

- Set `CLAUDE_CODE_NO_FLICKER=1` in your shell profile — clicking file paths in Claude Code's output will open them directly in Xcode.

<details>
<summary>Uninstall</summary>

```bash
brew uninstall --cask cc-xcode-connect
```

If installed manually, quit the app and delete `CCXcodeConnect.app` from your Applications folder.
</details>
