# QAFixMac

macOS native app that reproduces the `.claude/commands/qa-fix.md` workflow for
iOS QA defect fixing. It delegates agent execution to the local Claude Code CLI
(`claude -p --verbose --bare --output-format stream-json`) while the SwiftUI
layer handles Notion ticket retrieval, diff preview, git commit, and Notion
status updates.

## Requirements

- macOS 14.0 or newer (SwiftUI Observation framework)
- Xcode 16.0+
- Swift 5.9+
- Claude Code CLI 2.1.0+ (checked at launch)
- XcodeGen (`brew install xcodegen`) for project generation

## Setup

```bash
cd ~/Desktop/QAFixMac
xcodegen generate
open QAFixMac.xcodeproj
```

Build the `QAFixMac` scheme. On first launch provide:

- Notion integration token
- Notion database ID
- iOS repository path (selected via NSOpenPanel; stored as a security-scoped bookmark)
- Anthropic model (default: claude-sonnet-4-20250514)
- Max budget in USD per session

The app writes the Notion MCP config to
`~/Library/Application Support/QAFixMac/mcp.json` and passes it to every
`claude` subprocess via `--mcp-config`.

## Architecture

See `../internal-ios-repo/photocard/.omc/plans/qa-fix-mac-app.md` for the
consensus plan (Planner/Architect/Critic APPROVE, v3).

## CLI Spike

A standalone executable (`CLISpike` target) verifies the subprocess plumbing
used by `ClaudeCodeCLIClient`. Run it from a terminal after `xcodegen generate`:

```bash
xcodebuild -scheme CLISpike -destination 'platform=macOS' -configuration Debug build
~/Library/Developer/Xcode/DerivedData/QAFixMac-*/Build/Products/Debug/CLISpike \
  "Reply with the word PONG and nothing else." \
  ~/Desktop/QAFixMac
```

Expected output includes `[event #N] assistant`, `[event #N] result
(cost=..., duration=...ms)`, and `[spike] exit=0 events=N`.

## Distribution

Developer ID + Notarization only. App Store distribution is not possible
because `com.apple.security.process.exec` is required to spawn the Claude Code
CLI.
