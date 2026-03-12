# `ding agent-hook` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `ding agent-hook install/uninstall/status` commands that automatically register/remove ding notification hooks in AI coding tool config files (Claude Code, Gemini CLI).

**Architecture:** AgentHookManager handles all JSON config manipulation (read/write/detect). Three subcommands (install, uninstall, status) delegate to it. A command group wires them together under `ding agent-hook`.

**Tech Stack:** Swift 5.9, ArgumentParser, Foundation JSONSerialization

**Design doc:** `docs/plans/2026-03-12-agent-hook-command-design.md`

**CRITICAL CONSTRAINTS:**
- Do NOT add `import DingCore` inside any file in `Sources/DingCore/` — circular import causes build failure
- All files in `Sources/DingCore/` are part of DingCore — they must NOT import DingCore
- Use `import Foundation` and `import ArgumentParser` only

---

### Task 1: AgentHookManager — Core Logic

**Files:**
- Create: `Sources/DingCore/Services/AgentHookManager.swift`
- Test: `Tests/DingTests/AgentHookManagerTests.swift`

**Step 1: Write failing tests**

Create `Tests/DingTests/AgentHookManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import DingCore

@Suite("AgentHookManager Tests")
struct AgentHookManagerTests {

    // MARK: - Agent enum

    @Test("Agent display names")
    func agentDisplayNames() {
        #expect(Agent.claude.displayName == "Claude Code")
        #expect(Agent.gemini.displayName == "Gemini CLI")
    }

    @Test("Agent config file names")
    func agentConfigFileNames() {
        #expect(Agent.claude.configDirName == ".claude")
        #expect(Agent.gemini.configDirName == ".gemini")
    }

    // MARK: - Hook definitions

    @Test("Claude hook definitions")
    func claudeHookDefs() {
        let defs = Agent.claude.hookDefinitions
        #expect(defs.count == 2)
        #expect(defs[0].event == "Stop")
        #expect(defs[0].command == "ding hook --source claude --event Stop")
        #expect(defs[0].async == true)
        #expect(defs[1].event == "Notification")
        #expect(defs[1].async == true)
    }

    @Test("Gemini hook definitions")
    func geminiHookDefs() {
        let defs = Agent.gemini.hookDefinitions
        #expect(defs.count == 2)
        #expect(defs[0].event == "AfterAgent")
        #expect(defs[0].command == "ding hook --source gemini --event AfterAgent")
        #expect(defs[0].async == false)
    }

    // MARK: - JSON manipulation (Claude Code format)

    @Test("Install hooks into empty Claude config")
    func installClaudeEmpty() throws {
        let input: [String: Any] = ["permissions": ["allow": []]]
        let result = try AgentHookManager.installHooks(into: input, for: .claude)
        let hooks = result["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        #expect(stop.count == 1)
        let stopHooks = stop[0]["hooks"] as! [[String: Any]]
        #expect(stopHooks.count == 1)
        #expect((stopHooks[0]["command"] as! String).contains("ding hook"))
        #expect(stopHooks[0]["async"] as! Bool == true)
        // Permissions preserved
        #expect(result["permissions"] != nil)
    }

    @Test("Install hooks preserves existing non-ding hooks in Claude config")
    func installClaudePreserves() throws {
        let input: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff"]
                        ]
                    ]
                ]
            ]
        ]
        let result = try AgentHookManager.installHooks(into: input, for: .claude)
        let hooks = result["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        let stopHooks = stop[0]["hooks"] as! [[String: Any]]
        // afplay preserved + ding added
        #expect(stopHooks.count == 2)
        #expect((stopHooks[0]["command"] as! String).contains("afplay"))
        #expect((stopHooks[1]["command"] as! String).contains("ding hook"))
    }

    @Test("Install hooks updates existing ding hooks in Claude config")
    func installClaudeUpdates() throws {
        let input: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff"],
                            ["type": "command", "command": "ding hook --source claude --event Stop --old-flag", "async": true]
                        ]
                    ]
                ]
            ]
        ]
        let result = try AgentHookManager.installHooks(into: input, for: .claude)
        let hooks = result["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        let stopHooks = stop[0]["hooks"] as! [[String: Any]]
        // Old ding removed, new ding added, afplay preserved
        #expect(stopHooks.count == 2)
        #expect((stopHooks[0]["command"] as! String).contains("afplay"))
        #expect((stopHooks[1]["command"] as! String) == "ding hook --source claude --event Stop")
    }

    // MARK: - JSON manipulation (Gemini CLI format)

    @Test("Install hooks into empty Gemini config")
    func installGeminiEmpty() throws {
        let input: [String: Any] = ["security": ["auth": [:]]]
        let result = try AgentHookManager.installHooks(into: input, for: .gemini)
        let hooks = result["hooks"] as! [String: Any]
        let afterAgent = hooks["AfterAgent"] as! [[String: Any]]
        #expect(afterAgent.count == 1)
        let afterAgentHooks = afterAgent[0]["hooks"] as! [[String: Any]]
        #expect(afterAgentHooks.count == 1)
        #expect((afterAgentHooks[0]["command"] as! String).contains("ding hook"))
        // Security preserved
        #expect(result["security"] != nil)
    }

    // MARK: - Uninstall

    @Test("Uninstall removes only ding hooks from Claude config")
    func uninstallClaude() throws {
        let input: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff"],
                            ["type": "command", "command": "ding hook --source claude --event Stop", "async": true]
                        ]
                    ]
                ],
                "Notification": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "ding hook --source claude --event Notification", "async": true]
                        ]
                    ]
                ]
            ]
        ]
        let result = try AgentHookManager.uninstallHooks(from: input, for: .claude)
        let hooks = result["hooks"] as! [String: Any]
        // Stop should still exist (afplay remains)
        let stop = hooks["Stop"] as! [[String: Any]]
        let stopHooks = stop[0]["hooks"] as! [[String: Any]]
        #expect(stopHooks.count == 1)
        #expect((stopHooks[0]["command"] as! String).contains("afplay"))
        // Notification should be removed entirely (was only ding)
        #expect(hooks["Notification"] == nil)
    }

    @Test("Uninstall removes hooks object when empty")
    func uninstallRemovesEmptyHooks() throws {
        let input: [String: Any] = [
            "hooks": [
                "AfterAgent": [
                    [
                        "hooks": [
                            ["type": "command", "command": "ding hook --source gemini --event AfterAgent"]
                        ]
                    ]
                ],
                "Notification": [
                    [
                        "hooks": [
                            ["type": "command", "command": "ding hook --source gemini --event Notification"]
                        ]
                    ]
                ]
            ],
            "security": [:]
        ]
        let result = try AgentHookManager.uninstallHooks(from: input, for: .gemini)
        // hooks object should be removed entirely
        #expect(result["hooks"] == nil)
        // Other keys preserved
        #expect(result["security"] != nil)
    }

    // MARK: - Status detection

    @Test("Detect installed ding hooks")
    func detectHooks() {
        let config: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff"],
                            ["type": "command", "command": "ding hook --source claude --event Stop", "async": true]
                        ]
                    ]
                ],
                "Notification": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "ding hook --source claude --event Notification", "async": true]
                        ]
                    ]
                ]
            ]
        ]
        let events = AgentHookManager.detectDingHookEvents(in: config)
        #expect(events == ["Notification", "Stop"])  // sorted
    }

    @Test("Detect no ding hooks")
    func detectNoHooks() {
        let config: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff"]
                        ]
                    ]
                ]
            ]
        ]
        let events = AgentHookManager.detectDingHookEvents(in: config)
        #expect(events.isEmpty)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentHookManagerTests 2>&1 | head -20`
Expected: Compilation error — `Agent` and `AgentHookManager` not defined

**Step 3: Implement AgentHookManager**

Create `Sources/DingCore/Services/AgentHookManager.swift`:

```swift
import Foundation

// MARK: - Agent enum

public enum Agent: String, CaseIterable, ExpressibleByArgument {
    case claude
    case gemini

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .gemini: return "Gemini CLI"
        }
    }

    public var configDirName: String {
        switch self {
        case .claude: return ".claude"
        case .gemini: return ".gemini"
        }
    }

    public var configFilePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(configDirName).appendingPathComponent("settings.json")
    }

    public var isDetected: Bool {
        FileManager.default.fileExists(atPath: configFilePath.path)
    }

    public struct HookDefinition {
        public let event: String
        public let command: String
        public let async: Bool
    }

    public var hookDefinitions: [HookDefinition] {
        switch self {
        case .claude:
            return [
                HookDefinition(event: "Stop", command: "ding hook --source claude --event Stop", async: true),
                HookDefinition(event: "Notification", command: "ding hook --source claude --event Notification", async: true),
            ]
        case .gemini:
            return [
                HookDefinition(event: "AfterAgent", command: "ding hook --source gemini --event AfterAgent", async: false),
                HookDefinition(event: "Notification", command: "ding hook --source gemini --event Notification", async: false),
            ]
        }
    }
}

// MARK: - AgentHookManager

public enum AgentHookManager {

    private static let dingMarker = "ding hook"

    // MARK: - Install

    /// Adds/updates ding hook entries in the given config dictionary.
    /// Returns the modified dictionary. Does not write to disk.
    public static func installHooks(into config: [String: Any], for agent: Agent) throws -> [String: Any] {
        var result = config
        var hooks = (result["hooks"] as? [String: Any]) ?? [:]

        for def in agent.hookDefinitions {
            var hookEntry: [String: Any] = [
                "type": "command",
                "command": def.command,
            ]
            if def.async {
                hookEntry["async"] = true
            }

            switch agent {
            case .claude:
                hooks = installClaudeEvent(hooks, event: def.event, hookEntry: hookEntry)
            case .gemini:
                hooks = installGeminiEvent(hooks, event: def.event, hookEntry: hookEntry)
            }
        }

        result["hooks"] = hooks
        return result
    }

    private static func installClaudeEvent(_ hooks: [String: Any], event: String, hookEntry: [String: Any]) -> [String: Any] {
        var hooks = hooks
        var eventArray = (hooks[event] as? [[String: Any]]) ?? []

        // Find existing matcher:"*" entry, or create one
        var matcherIndex: Int?
        for (i, entry) in eventArray.enumerated() {
            if (entry["matcher"] as? String) == "*" {
                matcherIndex = i
                break
            }
        }

        if let idx = matcherIndex {
            var matcherEntry = eventArray[idx]
            var innerHooks = (matcherEntry["hooks"] as? [[String: Any]]) ?? []
            // Remove existing ding hooks
            innerHooks.removeAll { entry in
                (entry["command"] as? String)?.contains(dingMarker) == true
            }
            innerHooks.append(hookEntry)
            matcherEntry["hooks"] = innerHooks
            eventArray[idx] = matcherEntry
        } else {
            eventArray.append([
                "matcher": "*",
                "hooks": [hookEntry]
            ])
        }

        hooks[event] = eventArray
        return hooks
    }

    private static func installGeminiEvent(_ hooks: [String: Any], event: String, hookEntry: [String: Any]) -> [String: Any] {
        var hooks = hooks
        var eventArray = (hooks[event] as? [[String: Any]]) ?? []

        if eventArray.isEmpty {
            eventArray.append(["hooks": [hookEntry]])
        } else {
            var entry = eventArray[0]
            var innerHooks = (entry["hooks"] as? [[String: Any]]) ?? []
            innerHooks.removeAll { e in
                (e["command"] as? String)?.contains(dingMarker) == true
            }
            innerHooks.append(hookEntry)
            entry["hooks"] = innerHooks
            eventArray[0] = entry
        }

        hooks[event] = eventArray
        return hooks
    }

    // MARK: - Uninstall

    /// Removes all ding hook entries from the given config dictionary.
    /// Cleans up empty event arrays and the hooks object if empty.
    public static func uninstallHooks(from config: [String: Any], for agent: Agent) throws -> [String: Any] {
        var result = config
        guard var hooks = result["hooks"] as? [String: Any] else {
            return result
        }

        for def in agent.hookDefinitions {
            guard var eventArray = hooks[def.event] as? [[String: Any]] else { continue }

            for (i, var entry) in eventArray.enumerated() {
                guard var innerHooks = entry["hooks"] as? [[String: Any]] else { continue }
                innerHooks.removeAll { e in
                    (e["command"] as? String)?.contains(dingMarker) == true
                }
                if innerHooks.isEmpty {
                    // Mark for removal
                    entry["hooks"] = [] as [[String: Any]]
                } else {
                    entry["hooks"] = innerHooks
                }
                eventArray[i] = entry
            }

            // Remove entries with empty hooks arrays
            eventArray.removeAll { entry in
                (entry["hooks"] as? [[String: Any]])?.isEmpty == true
            }

            if eventArray.isEmpty {
                hooks.removeValue(forKey: def.event)
            } else {
                hooks[def.event] = eventArray
            }
        }

        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }

        return result
    }

    // MARK: - Status

    /// Returns sorted list of event names that have ding hooks configured.
    public static func detectDingHookEvents(in config: [String: Any]) -> [String] {
        guard let hooks = config["hooks"] as? [String: Any] else { return [] }
        var events: [String] = []

        for (event, value) in hooks {
            guard let eventArray = value as? [[String: Any]] else { continue }
            for entry in eventArray {
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { continue }
                if innerHooks.contains(where: { ($0["command"] as? String)?.contains(dingMarker) == true }) {
                    events.append(event)
                    break
                }
            }
        }

        return events.sorted()
    }

    // MARK: - File I/O

    /// Read config file as dictionary. Returns nil if file doesn't exist.
    public static func readConfig(for agent: Agent) throws -> [String: Any]? {
        let path = agent.configFilePath
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DingError.custom("Failed to parse \(path.path) as JSON object")
        }
        return json
    }

    /// Write config dictionary back to file with pretty printing.
    public static func writeConfig(_ config: [String: Any], for agent: Agent) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: agent.configFilePath, options: .atomic)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter AgentHookManagerTests 2>&1 | tail -10`
Expected: All tests pass

**Step 5: Commit**

```bash
git add Sources/DingCore/Services/AgentHookManager.swift Tests/DingTests/AgentHookManagerTests.swift
git commit -m "feat: add AgentHookManager with install/uninstall/status logic"
```

---

### Task 2: AgentHookCommand Group + Subcommands

**Files:**
- Create: `Sources/DingCore/Commands/AgentHookCommand.swift`
- Create: `Sources/DingCore/Commands/AgentHookInstallCommand.swift`
- Create: `Sources/DingCore/Commands/AgentHookUninstallCommand.swift`
- Create: `Sources/DingCore/Commands/AgentHookStatusCommand.swift`
- Modify: `Sources/ding/Ding.swift` (add to subcommands)

**Step 1: Create command group**

Create `Sources/DingCore/Commands/AgentHookCommand.swift`:

```swift
import ArgumentParser

public struct AgentHookCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "agent-hook",
        abstract: "Manage AI coding tool notification hooks",
        subcommands: [
            AgentHookInstallCommand.self,
            AgentHookUninstallCommand.self,
            AgentHookStatusCommand.self,
        ],
        defaultSubcommand: AgentHookStatusCommand.self
    )

    public init() {}
}
```

**Step 2: Create install subcommand**

Create `Sources/DingCore/Commands/AgentHookInstallCommand.swift`:

```swift
import ArgumentParser
import Foundation

public struct AgentHookInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install ding hooks into AI coding tool configs"
    )

    @Argument(help: "Agent to configure (claude, gemini). Omit to configure all detected agents.")
    var agent: Agent?

    public init() {}

    public func run() async throws {
        let agents = agent.map { [$0] } ?? Agent.allCases.map { $0 }

        for agent in agents {
            guard agent.isDetected else {
                print("✗ \(agent.displayName) — not found (\(agent.configFilePath.path) missing)")
                continue
            }

            do {
                guard var config = try AgentHookManager.readConfig(for: agent) else {
                    print("✗ \(agent.displayName) — could not read config")
                    continue
                }

                let hadDingHooks = !AgentHookManager.detectDingHookEvents(in: config).isEmpty
                config = try AgentHookManager.installHooks(into: config, for: agent)
                try AgentHookManager.writeConfig(config, for: agent)

                let events = agent.hookDefinitions.map(\.event).joined(separator: ", ")
                let verb = hadDingHooks ? "updated" : "installed"
                print("✓ \(agent.displayName) — hooks \(verb) (\(events))")
            } catch {
                print("✗ \(agent.displayName) — \(error.localizedDescription)")
            }
        }
    }
}
```

**Step 3: Create uninstall subcommand**

Create `Sources/DingCore/Commands/AgentHookUninstallCommand.swift`:

```swift
import ArgumentParser
import Foundation

public struct AgentHookUninstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove ding hooks from AI coding tool configs"
    )

    @Argument(help: "Agent to unconfigure (claude, gemini). Omit to unconfigure all detected agents.")
    var agent: Agent?

    public init() {}

    public func run() async throws {
        let agents = agent.map { [$0] } ?? Agent.allCases.map { $0 }

        for agent in agents {
            guard agent.isDetected else {
                print("✗ \(agent.displayName) — not found (\(agent.configFilePath.path) missing)")
                continue
            }

            do {
                guard var config = try AgentHookManager.readConfig(for: agent) else {
                    print("✗ \(agent.displayName) — could not read config")
                    continue
                }

                let hadDingHooks = !AgentHookManager.detectDingHookEvents(in: config).isEmpty
                guard hadDingHooks else {
                    print("✓ \(agent.displayName) — no ding hooks to remove")
                    continue
                }

                config = try AgentHookManager.uninstallHooks(from: config, for: agent)
                try AgentHookManager.writeConfig(config, for: agent)
                print("✓ \(agent.displayName) — hooks removed")
            } catch {
                print("✗ \(agent.displayName) — \(error.localizedDescription)")
            }
        }
    }
}
```

**Step 4: Create status subcommand**

Create `Sources/DingCore/Commands/AgentHookStatusCommand.swift`:

```swift
import ArgumentParser
import Foundation

public struct AgentHookStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show ding hook status for AI coding tools"
    )

    public init() {}

    // ANSI helpers
    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let reset = "\u{001B}[0m"

    public func run() async throws {
        for agent in Agent.allCases {
            guard agent.isDetected else {
                print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) not found")
                continue
            }

            do {
                guard let config = try AgentHookManager.readConfig(for: agent) else {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) could not read config")
                    continue
                }

                let events = AgentHookManager.detectDingHookEvents(in: config)
                if events.isEmpty {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) not configured")
                } else {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.green)✓\(Self.reset) \(events.joined(separator: ", "))")
                }
            } catch {
                print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) \(error.localizedDescription)")
            }
        }
    }
}
```

**Step 5: Register command group in Ding.swift**

Modify `Sources/ding/Ding.swift` — add `AgentHookCommand.self` to subcommands array:

```swift
subcommands: [
    WaitCommand.self,
    NotifyCommand.self,
    SetupCommand.self,
    StatusCommand.self,
    TestCommand.self,
    InstallHookCommand.self,
    UninstallHookCommand.self,
    HookCommand.self,
    AgentHookCommand.self,
]
```

**Step 6: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 7: Commit**

```bash
git add Sources/DingCore/Commands/AgentHook*.swift Sources/ding/Ding.swift
git commit -m "feat: add ding agent-hook install/uninstall/status commands"
```

---

### Task 3: Manual E2E Verification

**Step 1: Build release binary**

Run: `swift build -c release 2>&1 | tail -3`
Expected: Build succeeded

**Step 2: Test status (before any changes)**

Run: `.build/release/ding agent-hook status`
Expected: Shows current hook state for Claude Code and Gemini CLI

**Step 3: Test install (idempotent — hooks already exist)**

Run: `.build/release/ding agent-hook install`
Expected: `✓ Claude Code — hooks updated (Stop, Notification)` and `✓ Gemini CLI — hooks updated (AfterAgent, Notification)`

**Step 4: Verify configs preserved non-ding hooks**

Run: `cat ~/.claude/settings.json | python3 -m json.tool`
Expected: afplay hooks still present alongside ding hooks

**Step 5: Test uninstall**

Run: `.build/release/ding agent-hook uninstall claude`
Expected: `✓ Claude Code — hooks removed`

**Step 6: Verify uninstall preserved afplay hooks**

Run: `cat ~/.claude/settings.json | python3 -m json.tool`
Expected: afplay hooks still present, ding hooks gone

**Step 7: Re-install to restore**

Run: `.build/release/ding agent-hook install claude`
Expected: `✓ Claude Code — hooks installed (Stop, Notification)`

**Step 8: Install binary**

Run: `sudo cp .build/release/ding /usr/local/bin/ding`

**Step 9: Commit (if any fixes were needed)**

```bash
git add -A && git commit -m "fix: agent-hook adjustments from E2E testing"
```
