# OpenCode Ding Plugin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an OpenCode notification plugin with contextual messages (prompt summaries) and integrate it into `ding agent-hook install/uninstall/status`.

**Architecture:** TypeScript plugin using `@opencode-ai/plugin` API captures user prompts via `chat.message` hook and sends notifications via `ding notify` CLI on `session.idle`. Swift CLI gets dedup logic (`hook_source == "opencode-plugin"` → skip) and OpenCode agent support in `AgentHookManager`.

**Tech Stack:** TypeScript (OpenCode plugin), Swift 5.9 (CLI changes)

**Design doc:** `docs/plans/2026-03-12-opencode-plugin-design.md`

**CRITICAL CONSTRAINTS:**
- Do NOT add `import DingCore` inside any file in `Sources/DingCore/`
- Plugin must use `child_process.spawn` to call `ding notify` (not HTTP directly)
- Plugin lives at `~/.config/opencode/plugins/opencode-ding/` when installed
- Development source at `/Users/sijun/coding/ding/opencode-plugin/`

---

### Task 1: Create the OpenCode Plugin

**Files:**
- Create: `opencode-plugin/package.json`
- Create: `opencode-plugin/index.ts`

**Step 1: Create package.json**

Create `opencode-plugin/package.json`:

```json
{
  "name": "opencode-ding",
  "version": "0.1.0",
  "description": "Ding push notifications for OpenCode",
  "main": "index.ts",
  "dependencies": {
    "@opencode-ai/plugin": "^1.2.24"
  }
}
```

**Step 2: Create plugin entry point**

Create `opencode-plugin/index.ts`:

```typescript
import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "child_process"

const plugin: Plugin = async (input) => {
  // State: track last user prompt per session
  let lastPrompt: string | null = null
  let lastSessionID: string | null = null

  function truncate(text: string, maxLength: number): string {
    const cleaned = text.replace(/\n/g, " ").trim()
    if (cleaned.length <= maxLength) return cleaned
    return cleaned.substring(0, maxLength) + "…"
  }

  function sendNotification(body: string, status: string) {
    const proc = spawn("ding", ["notify", body, "--title", "ding · OpenCode", "--status", status], {
      stdio: "ignore",
      detached: true,
    })
    proc.unref()
  }

  return {
    "chat.message": async (_input, output) => {
      // Cache the user's prompt text from parts
      const textParts = output.parts.filter((p) => p.type === "text")
      if (textParts.length > 0) {
        const text = textParts.map((p) => ("text" in p ? p.text : "")).join(" ")
        if (text.trim()) {
          lastPrompt = text.trim()
          lastSessionID = _input.sessionID
        }
      }
    },

    event: async ({ event }) => {
      // Send notification when main session becomes idle
      if (event.type === "session.idle") {
        const sessionID = event.properties.sessionID
        if (sessionID !== lastSessionID) return // skip subagent sessions

        const cwd = input.project?.path || input.directory || process.cwd()
        const summary = lastPrompt ? `Done: ${truncate(lastPrompt, 80)}` : "Task completed"
        const body = `${cwd}\n${summary}`

        sendNotification(body, "success")

        lastPrompt = null
        lastSessionID = null
      }

      // Send notification on session error
      if (event.type === "session.error") {
        const cwd = input.project?.path || input.directory || process.cwd()
        const error = event.properties.error
        const msg = error && "data" in error && "message" in (error as any).data
          ? (error as any).data.message
          : "Unknown error"
        const body = `${cwd}\nFailed: ${truncate(msg, 80)}`

        sendNotification(body, "failure")

        lastPrompt = null
        lastSessionID = null
      }
    },
  }
}

export default plugin
```

**Step 3: Install dependencies**

Run: `cd /Users/sijun/coding/ding/opencode-plugin && bun install`
Expected: Dependencies installed

**Step 4: Commit**

```bash
git add opencode-plugin/
git commit -m "feat: add OpenCode ding notification plugin"
```

---

### Task 2: `ding hook` Dedup Logic

**Files:**
- Modify: `Sources/DingCore/Commands/HookCommand.swift`

**Step 1: Add `hook_source` to HookInput struct**

In `HookCommand.swift`, add to the `HookInput` struct:

```swift
let hook_source: String?
```

**Step 2: Add early return in `run()` method**

At the top of `run()`, after reading stdin, add:

```swift
// Skip if OpenCode plugin handles notifications
if input?.hook_source == "opencode-plugin" {
    return
}
```

**Step 3: Remove the debug dump code**

Remove the temporary debug dump that writes to `~/.config/ding/last-hook-stdin.json`. It was added for investigation and is no longer needed.

**Step 4: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: Build succeeded

**Step 5: Run tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/DingCore/Commands/HookCommand.swift
git commit -m "feat: skip ding hook when OpenCode plugin handles notification"
```

---

### Task 3: Add OpenCode to AgentHookManager

**Files:**
- Modify: `Sources/DingCore/Services/AgentHookManager.swift`
- Modify: `Tests/DingTests/AgentHookManagerTests.swift`

This task extends the existing Agent enum and AgentHookManager with OpenCode support. OpenCode installation is fundamentally different from Claude/Gemini (plugin files + opencode.json plugin array, not settings.json hooks).

**Step 1: Add tests for OpenCode agent**

Add to `Tests/DingTests/AgentHookManagerTests.swift`:

```swift
// MARK: - OpenCode agent

@Test("OpenCode display name")
func opencodeDisplayName() {
    #expect(Agent.opencode.displayName == "OpenCode")
}

@Test("OpenCode config dir name")
func opencodeConfigDirName() {
    #expect(Agent.opencode.configDirName == ".config/opencode")
}

@Test("OpenCode has no hook definitions")
func opencodeHookDefs() {
    #expect(Agent.opencode.hookDefinitions.isEmpty)
}

// MARK: - OpenCode JSON manipulation

@Test("Install OpenCode plugin into config without existing plugins")
func installOpencodeEmpty() throws {
    let input: [String: Any] = ["$schema": "https://opencode.ai/config.json"]
    let result = try AgentHookManager.installOpenCodePlugin(into: input)
    let plugins = result["plugin"] as! [String]
    #expect(plugins.contains("./plugins/opencode-ding"))
}

@Test("Install OpenCode plugin preserves existing plugins")
func installOpencodePreserves() throws {
    let input: [String: Any] = [
        "plugin": ["oh-my-opencode@latest", "opencode-antigravity-auth@1.6.0"]
    ]
    let result = try AgentHookManager.installOpenCodePlugin(into: input)
    let plugins = result["plugin"] as! [String]
    #expect(plugins.count == 3)
    #expect(plugins.contains("oh-my-opencode@latest"))
    #expect(plugins.contains("./plugins/opencode-ding"))
}

@Test("Install OpenCode plugin is idempotent")
func installOpencodeIdempotent() throws {
    let input: [String: Any] = [
        "plugin": ["oh-my-opencode@latest", "./plugins/opencode-ding"]
    ]
    let result = try AgentHookManager.installOpenCodePlugin(into: input)
    let plugins = result["plugin"] as! [String]
    #expect(plugins.count == 2)  // no duplicate
}

@Test("Uninstall OpenCode plugin removes entry")
func uninstallOpencode() throws {
    let input: [String: Any] = [
        "plugin": ["oh-my-opencode@latest", "./plugins/opencode-ding"]
    ]
    let result = try AgentHookManager.uninstallOpenCodePlugin(from: input)
    let plugins = result["plugin"] as! [String]
    #expect(plugins.count == 1)
    #expect(plugins.contains("oh-my-opencode@latest"))
    #expect(!plugins.contains("./plugins/opencode-ding"))
}

@Test("Uninstall OpenCode plugin removes plugin array if empty")
func uninstallOpencodeEmptyArray() throws {
    let input: [String: Any] = [
        "plugin": ["./plugins/opencode-ding"]
    ]
    let result = try AgentHookManager.uninstallOpenCodePlugin(from: input)
    #expect(result["plugin"] == nil)
}

@Test("Detect OpenCode plugin installed")
func detectOpencodePlugin() {
    let config: [String: Any] = [
        "plugin": ["oh-my-opencode@latest", "./plugins/opencode-ding"]
    ]
    #expect(AgentHookManager.isOpenCodePluginInstalled(in: config) == true)
}

@Test("Detect OpenCode plugin not installed")
func detectOpencodePluginMissing() {
    let config: [String: Any] = [
        "plugin": ["oh-my-opencode@latest"]
    ]
    #expect(AgentHookManager.isOpenCodePluginInstalled(in: config) == false)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentHookManagerTests 2>&1 | head -10`
Expected: Compilation errors

**Step 3: Extend Agent enum**

Add `opencode` case to Agent enum in `AgentHookManager.swift`:

```swift
public enum Agent: String, CaseIterable, ExpressibleByArgument {
    case claude
    case gemini
    case opencode

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .gemini: return "Gemini CLI"
        case .opencode: return "OpenCode"
        }
    }

    public var configDirName: String {
        switch self {
        case .claude: return ".claude"
        case .gemini: return ".gemini"
        case .opencode: return ".config/opencode"
        }
    }

    public var configFileName: String {
        switch self {
        case .claude, .gemini: return "settings.json"
        case .opencode: return "opencode.json"
        }
    }

    public var configFilePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(configDirName).appendingPathComponent(configFileName)
    }

    // ... isDetected stays the same

    public var hookDefinitions: [HookDefinition] {
        switch self {
        case .claude:
            // ... existing
        case .gemini:
            // ... existing
        case .opencode:
            return []  // OpenCode uses plugin, not hooks
        }
    }
}
```

**Step 4: Add OpenCode-specific methods to AgentHookManager**

Add these to `AgentHookManager`:

```swift
// MARK: - OpenCode Plugin

private static let opencodePluginPath = "./plugins/opencode-ding"

public static func installOpenCodePlugin(into config: [String: Any]) throws -> [String: Any] {
    var result = config
    var plugins = (result["plugin"] as? [String]) ?? []

    if !plugins.contains(where: { $0.contains("opencode-ding") }) {
        plugins.append(opencodePluginPath)
    }

    result["plugin"] = plugins
    return result
}

public static func uninstallOpenCodePlugin(from config: [String: Any]) throws -> [String: Any] {
    var result = config
    guard var plugins = result["plugin"] as? [String] else {
        return result
    }

    plugins.removeAll { $0.contains("opencode-ding") }

    if plugins.isEmpty {
        result.removeValue(forKey: "plugin")
    } else {
        result["plugin"] = plugins
    }

    return result
}

public static func isOpenCodePluginInstalled(in config: [String: Any]) -> Bool {
    guard let plugins = config["plugin"] as? [String] else { return false }
    return plugins.contains { $0.contains("opencode-ding") }
}
```

**Step 5: Run tests**

Run: `swift test --filter AgentHookManagerTests 2>&1 | tail -10`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/DingCore/Services/AgentHookManager.swift Tests/DingTests/AgentHookManagerTests.swift
git commit -m "feat: add OpenCode agent with plugin install/uninstall/status"
```

---

### Task 4: Update Commands for OpenCode

**Files:**
- Modify: `Sources/DingCore/Commands/AgentHookInstallCommand.swift`
- Modify: `Sources/DingCore/Commands/AgentHookUninstallCommand.swift`
- Modify: `Sources/DingCore/Commands/AgentHookStatusCommand.swift`

The install/uninstall commands need special handling for OpenCode because it uses plugin files instead of hook entries. The key changes:

**Install command** — after writing opencode.json, also copy plugin files to `~/.config/opencode/plugins/opencode-ding/`:

```swift
case .opencode:
    // 1. Copy plugin files to ~/.config/opencode/plugins/opencode-ding/
    let pluginDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/opencode/plugins/opencode-ding")
    try AgentHookManager.installOpenCodePluginFiles(to: pluginDir)

    // 2. Update opencode.json
    config = try AgentHookManager.installOpenCodePlugin(into: config)
    try AgentHookManager.writeConfig(config, for: agent)
    print("✓ \(agent.displayName) — plugin \(hadDingPlugin ? "updated" : "installed")")
```

**Uninstall command** — remove plugin files and opencode.json entry:

```swift
case .opencode:
    config = try AgentHookManager.uninstallOpenCodePlugin(from: config)
    try AgentHookManager.writeConfig(config, for: agent)
    // Remove plugin directory
    let pluginDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/opencode/plugins/opencode-ding")
    try? FileManager.default.removeItem(at: pluginDir)
    print("✓ \(agent.displayName) — plugin removed")
```

**Status command** — use `isOpenCodePluginInstalled`:

```swift
case .opencode:
    if AgentHookManager.isOpenCodePluginInstalled(in: config) {
        print("... ✓ plugin installed")
    } else {
        print("... ✗ not configured")
    }
```

**AgentHookManager** needs a new method to copy plugin files:

```swift
/// Embeds and writes the OpenCode plugin files to the target directory.
public static func installOpenCodePluginFiles(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // package.json
    let packageJSON = """
    {
      "name": "opencode-ding",
      "version": "0.1.0",
      "description": "Ding push notifications for OpenCode",
      "main": "index.ts",
      "dependencies": {
        "@opencode-ai/plugin": "^1.2.24"
      }
    }
    """
    try packageJSON.write(to: directory.appendingPathComponent("package.json"),
                          atomically: true, encoding: .utf8)

    // index.ts (full plugin source embedded as string)
    let indexTS = """
    import type { Plugin } from "@opencode-ai/plugin"
    import { spawn } from "child_process"
    // ... full plugin source
    """
    try indexTS.write(to: directory.appendingPathComponent("index.ts"),
                      atomically: true, encoding: .utf8)
}
```

The full plugin source from Task 1's `index.ts` will be embedded as a Swift string literal.

**Step 1: Update AgentHookManager with file installation method**

Add `installOpenCodePluginFiles(to:)` method with embedded plugin source.

**Step 2: Update install command for OpenCode branching**

Add OpenCode-specific logic to `AgentHookInstallCommand.run()`.

**Step 3: Update uninstall command for OpenCode branching**

Add OpenCode-specific logic to `AgentHookUninstallCommand.run()`.

**Step 4: Update status command for OpenCode**

Add OpenCode-specific display in `AgentHookStatusCommand.run()`.

**Step 5: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: Build succeeded

**Step 6: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass

**Step 7: Commit**

```bash
git add Sources/DingCore/Commands/AgentHook*.swift Sources/DingCore/Services/AgentHookManager.swift
git commit -m "feat: integrate OpenCode plugin into agent-hook install/uninstall/status"
```

---

### Task 5: E2E Verification

**Step 1: Build release**

Run: `swift build -c release 2>&1 | tail -3`

**Step 2: Test install**

Run: `.build/release/ding agent-hook install`
Expected: All three agents show ✓

**Step 3: Verify plugin files created**

Run: `ls ~/.config/opencode/plugins/opencode-ding/`
Expected: `package.json` and `index.ts`

**Step 4: Verify opencode.json updated**

Run: `cat ~/.config/opencode/opencode.json | python3 -c "import sys,json; print(json.load(sys.stdin).get('plugin'))"`
Expected: List includes `"./plugins/opencode-ding"`

**Step 5: Test status**

Run: `.build/release/ding agent-hook status`
Expected: All three agents show ✓

**Step 6: Test uninstall opencode**

Run: `.build/release/ding agent-hook uninstall opencode`
Expected: `✓ OpenCode — plugin removed`

**Step 7: Verify cleanup**

Run: `ls ~/.config/opencode/plugins/opencode-ding/ 2>/dev/null && echo "EXISTS" || echo "REMOVED"`
Expected: REMOVED

**Step 8: Reinstall and install binary**

Run: `.build/release/ding agent-hook install opencode`
Run: `sudo cp .build/release/ding /usr/local/bin/ding`

**Step 9: Install plugin dependencies**

Run: `cd ~/.config/opencode/plugins/opencode-ding && bun install`

**Step 10: Restart OpenCode to load plugin, test notification**

Trigger a prompt in OpenCode, wait for idle, verify notification arrives with prompt context.
