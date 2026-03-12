# Design: OpenCode Ding Plugin + Dedup Logic

## Overview

Rebuild the OpenCode notification plugin using the `@opencode-ai/plugin` API to provide context-rich notifications (actual prompt content, error details). Integrate installation/uninstall into the existing `ding agent-hook` command. Add dedup logic to `ding hook` to prevent duplicate notifications when OpenCode fires Claude Code hooks.

## Problem

OpenCode internally fires Claude Code hooks (via oh-my-opencode's compatibility layer), but the Stop hook stdin lacks the `prompt` field — notifications show generic "Task completed" instead of contextual messages.

## Solution: Two Changes

### 1. OpenCode Plugin

A local plugin using `@opencode-ai/plugin` `event` handler to:
- Cache the user's prompt from `message.updated` events (role: "user")
- Detect session completion via `session.idle` events
- Send contextual notification via `ding notify` CLI

### 2. `ding hook` Dedup

When stdin JSON has `hook_source == "opencode-plugin"`, skip notification — the plugin handles it.

## Data Flow

```
User sends prompt
  → message.updated (role: "user") → plugin caches lastPrompt + sessionID

Agent works (tool calls, etc.)
  → events flow, plugin ignores

Session becomes idle
  → session.idle → plugin checks sessionID matches cached
  → spawns: ding notify "{cwd}\nDone: {prompt}" --title "ding · OpenCode" --status success
  → cache cleared

Session errors
  → session.error → plugin detects
  → spawns: ding notify "{cwd}\nFailed: {error}" --title "ding · OpenCode" --status failure
```

## Subagent Filtering

Only main sessions trigger notifications. The plugin caches sessionID alongside the prompt from `message.updated`. On `session.idle`, it only sends a notification if the idle sessionID matches the cached sessionID. Subagent sessions don't go through `chat.message`, so they're naturally filtered out.

## Plugin Source

```
~/.config/opencode/plugins/opencode-ding/
├── package.json     # name: "opencode-ding"
├── index.ts         # Plugin entry point
```

### index.ts (Conceptual)

```typescript
import type { Plugin } from "@opencode-ai/plugin"

const plugin: Plugin = async (input) => {
  let lastPrompt: string | null = null
  let lastSessionID: string | null = null
  const cwd = input.project?.path || process.cwd()

  return {
    event: async ({ event }) => {
      // Cache prompt from user messages
      if (event.type === "message.updated") {
        const msg = event.properties.info
        if (msg.role === "user" && !msg.parentID?.includes("agent-")) {
          lastPrompt = extractPrompt(msg)
          lastSessionID = msg.sessionID
        }
      }

      // Send notification on session idle
      if (event.type === "session.idle") {
        const sessionID = event.properties.sessionID
        if (sessionID !== lastSessionID) return  // skip subagents

        const prompt = lastPrompt
        lastPrompt = null
        lastSessionID = null

        const summary = prompt ? `Done: ${truncate(prompt, 80)}` : "Task completed"
        const body = `${cwd}\n${summary}`
        spawn("ding", ["notify", body, "--title", "ding · OpenCode", "--status", "success"])
      }

      // Send notification on session error
      if (event.type === "session.error") {
        const error = event.properties.error
        const msg = error?.message || "Unknown error"
        const body = `${cwd}\nFailed: ${truncate(msg, 80)}`
        spawn("ding", ["notify", body, "--title", "ding · OpenCode", "--status", "failure"])
        lastPrompt = null
        lastSessionID = null
      }
    }
  }
}
```

## Integration with `ding agent-hook`

### Agent enum extension

Add `opencode` to the Agent enum alongside `claude` and `gemini`.

### Detection

OpenCode is "installed" if `~/.config/opencode/opencode.json` exists.

### Install

1. Create `~/.config/opencode/plugins/opencode-ding/` with plugin files (package.json, index.ts)
2. Read `~/.config/opencode/opencode.json`
3. Add `"./plugins/opencode-ding"` to the `plugin` array (if not already present)
4. Write back

### Uninstall

1. Remove `"./plugins/opencode-ding"` from the `plugin` array
2. Delete `~/.config/opencode/plugins/opencode-ding/` directory

### Status

Check if `"./plugins/opencode-ding"` (or any path containing `opencode-ding`) is in the plugin array.

### Output

```
$ ding agent-hook install
✓ Claude Code — hooks updated (Stop, Notification)
✓ Gemini CLI  — hooks updated (AfterAgent, Notification)
✓ OpenCode    — plugin installed

$ ding agent-hook status
Claude Code  ✓ Stop, Notification
Gemini CLI   ✓ AfterAgent, Notification
OpenCode     ✓ plugin installed

$ ding agent-hook uninstall opencode
✓ OpenCode — plugin removed
```

## `ding hook` Dedup Change

In `HookCommand.swift`, add early return:

```swift
public func run() async throws {
    let (input, rawData) = readStdinJSON()

    // Skip if OpenCode plugin handles notifications
    if input?.hookSource == "opencode-plugin" { return }

    // ... rest of existing logic
}
```

Add `hookSource` field to `HookInput`:
```swift
private struct HookInput: Decodable {
    // ... existing fields
    let hook_source: String?
}
```

## Notification Format

| Source | Title | Body |
|---|---|---|
| OpenCode (success) | `ding · OpenCode` | `/Users/sijun/coding/ding`<br>`Done: {prompt summary}` |
| OpenCode (failure) | `ding · OpenCode` | `/Users/sijun/coding/ding`<br>`Failed: {error message}` |
| OpenCode (no prompt) | `ding · OpenCode` | `/Users/sijun/coding/ding`<br>`Task completed` |
