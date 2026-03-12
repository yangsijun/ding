import Foundation
import ArgumentParser

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
        public let `async`: Bool
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
                    entry["hooks"] = [] as [[String: Any]]
                } else {
                    entry["hooks"] = innerHooks
                }
                eventArray[i] = entry
            }

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

    public static func readConfig(for agent: Agent) throws -> [String: Any]? {
        let path = agent.configFilePath
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DingError.decodingError("Failed to parse \(path.path) as JSON object")
        }
        return json
    }

    public static func writeConfig(_ config: [String: Any], for agent: Agent) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: agent.configFilePath, options: .atomic)
    }
}
