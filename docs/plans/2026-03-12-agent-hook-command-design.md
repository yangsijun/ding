# Design: `ding agent-hook` Command Group

## Overview

Automate registration and removal of ding notification hooks across AI coding tools (Claude Code, Gemini CLI). Detects installed agents and surgically modifies their config files to add/update/remove ding hook entries while preserving all existing non-ding hooks.

## Command Interface

```
ding agent-hook install [claude|gemini]     # no arg = all detected
ding agent-hook uninstall [claude|gemini]   # no arg = all detected
ding agent-hook status                      # show what's configured
```

### Detection

An agent is "installed" if its config file exists:
- Claude Code: `~/.claude/settings.json`
- Gemini CLI: `~/.gemini/settings.json`

### Output

```
# Install (fresh)
$ ding agent-hook install
✓ Claude Code — hooks installed (Stop, Notification)
✓ Gemini CLI  — hooks installed (AfterAgent, Notification)

# Install (update)
$ ding agent-hook install
✓ Claude Code — hooks updated (Stop, Notification)
✓ Gemini CLI  — hooks updated (AfterAgent, Notification)

# Agent not found
$ ding agent-hook install claude
✗ Claude Code — not found (~/.claude/settings.json missing)

# Status
$ ding agent-hook status
Claude Code  ✓ Stop, Notification
Gemini CLI   ✗ not configured

# Uninstall
$ ding agent-hook uninstall
✓ Claude Code — hooks removed
✓ Gemini CLI  — hooks removed
```

## Hook Definitions

| Agent | Event | Command | Async |
|---|---|---|---|
| Claude Code | Stop | `ding hook --source claude --event Stop` | true |
| Claude Code | Notification | `ding hook --source claude --event Notification` | true |
| Gemini CLI | AfterAgent | `ding hook --source gemini --event AfterAgent` | — |
| Gemini CLI | Notification | `ding hook --source gemini --event Notification` | — |

## JSON Manipulation Strategy

Use `JSONSerialization` (not Codable) to preserve unknown fields and structure.

### Identification

A hook entry belongs to ding if its `command` field contains `"ding hook"`.

### Claude Code Structure

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "afplay ..." },
          { "type": "command", "command": "ding hook --source claude --event Stop", "async": true }
        ]
      }
    ]
  }
}
```

- For each event: find the `matcher: "*"` entry (or create one)
- Within its `hooks` array: remove any entry where `command` contains `"ding hook"`, then append our new entry
- Non-ding hooks (afplay, etc.) are untouched

### Gemini CLI Structure

```json
{
  "hooks": {
    "AfterAgent": [
      {
        "hooks": [
          { "type": "command", "command": "ding hook --source gemini --event AfterAgent" }
        ]
      }
    ]
  }
}
```

- Simpler structure (no `matcher`). For each event: find or create the entry
- Within `hooks` array: remove any `"ding hook"` entries, append ours

### Uninstall

Same traversal, but only remove `"ding hook"` entries. If a hooks array becomes empty after removal, remove the entire event key. If the hooks object becomes empty, remove it entirely.

## File Structure

```
Sources/DingCore/Commands/
├── AgentHookCommand.swift          # Command group
├── AgentHookInstallCommand.swift   # install subcommand
├── AgentHookUninstallCommand.swift # uninstall subcommand
├── AgentHookStatusCommand.swift    # status subcommand

Sources/DingCore/
├── AgentHookManager.swift          # Shared logic
```

## AgentHookManager

```swift
enum Agent: String, CaseIterable { case claude, gemini }

// Core API
func configPath(for agent: Agent) -> URL
func isInstalled(_ agent: Agent) -> Bool
func hookDefinitions(for agent: Agent) -> [(event: String, command: String, async: Bool)]
func installHooks(for agent: Agent) throws -> InstallResult
func uninstallHooks(for agent: Agent) throws -> UninstallResult
func hookStatus(for agent: Agent) -> [String]?  // configured event names, or nil
```

## Error Handling

- File not found → report "not found"
- Parse error → report "config file corrupted, skipping"
- Write error → report failure, don't crash
- Never exit with non-zero for partial failures (some agents succeed, some fail)
