import Foundation
import ArgumentParser

// MARK: - Agent enum

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
                HookDefinition(event: "Stop", command: "ding _dispatch --source claude --event Stop", async: true),
                HookDefinition(event: "Notification", command: "ding _dispatch --source claude --event Notification", async: true),
            ]
        case .gemini:
            return [
                HookDefinition(event: "AfterAgent", command: "ding _dispatch --source gemini --event AfterAgent", async: false),
                HookDefinition(event: "Notification", command: "ding _dispatch --source gemini --event Notification", async: false),
            ]
        case .opencode:
            return []
        }
    }
}

// MARK: - AgentHookManager

public enum AgentHookManager {

    private static let dingMarker = "ding _dispatch"

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
            case .opencode:
                break  // OpenCode uses plugins, not hooks
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

    // MARK: - OpenCode Plugin Management

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
        guard var plugins = result["plugin"] as? [String] else { return result }
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

    public static func installOpenCodePluginFiles(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

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

        let indexTS = """
        import type { Plugin } from "@opencode-ai/plugin"
        import { spawn } from "child_process"

        const plugin: Plugin = async (input) => {
          let lastPrompt: string | null = null
          let mainSessionID: string | null = null
          let lastUserMessageID: string | null = null

          function truncate(text: string, maxLength: number): string {
            const cleaned = text.replace(/\\n/g, " ").trim()
            if (cleaned.length <= maxLength) return cleaned
            return cleaned.substring(0, maxLength) + "\u{2026}"
          }

          function shortenHome(dir: string): string {
            const home = process.env.HOME || process.env.USERPROFILE || ""
            if (home && dir.startsWith(home)) return "~" + dir.slice(home.length)
            return dir
          }

          function sendNotification(body: string, status: string) {
            const proc = spawn("ding", ["notify", body, "--title", "ding \u{00b7} OpenCode", "--status", status], {
              stdio: "ignore",
              detached: true,
            })
            proc.unref()
          }

          return {
            event: async ({ event }) => {
              // Track user prompts via message events
              if (event.type === "message.updated") {
                const msg = (event.properties as any).info
                if (msg?.role === "user") {
                  mainSessionID = msg.sessionID
                  lastUserMessageID = msg.id
                }
              }

              // Capture user's typed text from part updates
              if (event.type === "message.part.updated") {
                const part = (event.properties as any).part
                if (
                  part?.type === "text" &&
                  !part.synthetic &&
                  part.messageID === lastUserMessageID
                ) {
                  const text = (part.text || "").replace(/\\n/g, " ").trim()
                  if (text) {
                    lastPrompt = text
                  }
                }
              }

              if (event.type === "session.idle") {
                const sessionID = event.properties.sessionID
                if (mainSessionID && sessionID !== mainSessionID) return

                const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
                const summary = lastPrompt ? `Done: ${truncate(lastPrompt, 80)}` : "Task completed"
                const body = `${cwd}\\n${summary}`

                sendNotification(body, "success")

                lastPrompt = null
              }

              if (event.type === "session.error") {
                const sessionID = (event.properties as any).sessionID
                if (mainSessionID && sessionID !== mainSessionID) return

                const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
                const error = event.properties.error
                const msg =
                  error && "data" in error && typeof (error as any).data?.message === "string"
                    ? (error as any).data.message
                    : "Unknown error"
                const body = `${cwd}\\nFailed: ${truncate(msg, 80)}`

                sendNotification(body, "failure")
              }

              if (event.type === "question.asked") {
                const props = event.properties as { sessionID?: string; questions?: Array<{ question?: string; header?: string }> }
                const sessionID = props.sessionID
                if (mainSessionID && sessionID !== mainSessionID) return

                const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
                const question = props.questions?.[0]?.header || props.questions?.[0]?.question || "Needs your input"
                const body = `${cwd}\\nAsked: ${truncate(question, 80)}`

                sendNotification(body, "warning")
              }
            },
          }
        }

        export default plugin
        """
        try indexTS.write(to: directory.appendingPathComponent("index.ts"),
                          atomically: true, encoding: .utf8)
    }
}
