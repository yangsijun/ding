import Testing
import Foundation
@testable import DingCore

@Suite("AgentHookManager Tests")
struct AgentHookManagerTests {

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
        #expect(plugins.count == 2)
    }

    @Test("Uninstall OpenCode plugin removes entry")
    func uninstallOpencode() throws {
        let input: [String: Any] = [
            "plugin": ["oh-my-opencode@latest", "./plugins/opencode-ding"]
        ]
        let result = try AgentHookManager.uninstallOpenCodePlugin(from: input)
        let plugins = result["plugin"] as! [String]
        #expect(plugins.count == 1)
        #expect(!plugins.contains { ($0 as String).contains("opencode-ding") })
    }

    @Test("Uninstall OpenCode plugin removes plugin key if empty")
    func uninstallOpencodeEmptyArray() throws {
        let input: [String: Any] = ["plugin": ["./plugins/opencode-ding"]]
        let result = try AgentHookManager.uninstallOpenCodePlugin(from: input)
        #expect(result["plugin"] == nil)
    }

    @Test("Detect OpenCode plugin installed")
    func detectOpencodePlugin() {
        let config: [String: Any] = ["plugin": ["oh-my-opencode@latest", "./plugins/opencode-ding"]]
        #expect(AgentHookManager.isOpenCodePluginInstalled(in: config) == true)
    }

    @Test("Detect OpenCode plugin not installed")
    func detectOpencodePluginMissing() {
        let config: [String: Any] = ["plugin": ["oh-my-opencode@latest"]]
        #expect(AgentHookManager.isOpenCodePluginInstalled(in: config) == false)
    }

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
