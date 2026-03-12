import ArgumentParser
import Foundation

public struct HookUninstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove notification hooks",
        discussion: """
        Without arguments: removes shell hook.
        With agent name: removes hook from AI coding tool config.

        Examples:
          ding hook uninstall            # shell hook
          ding hook uninstall claude     # Claude Code hook
        """
    )

    @Argument(help: "AI coding tool to unconfigure (claude, gemini, opencode). Omit for shell hook.")
    var agent: Agent?

    public init() {}

    public func run() async throws {
        if let agent {
            try await uninstallAgentHook(agent)
        } else {
            try await uninstallShellHook()
        }
    }

    // MARK: - Agent Hook

    private func uninstallAgentHook(_ agent: Agent) async throws {
        guard agent.isDetected else {
            print("✗ \(agent.displayName) — not found (\(agent.configFilePath.path) missing)")
            return
        }

        guard var config = try AgentHookManager.readConfig(for: agent) else {
            print("✗ \(agent.displayName) — could not read config")
            return
        }

        switch agent {
        case .opencode:
            let hadPlugin = AgentHookManager.isOpenCodePluginInstalled(in: config)
            guard hadPlugin else {
                print("✓ \(agent.displayName) — no plugin to remove")
                return
            }
            config = try AgentHookManager.uninstallOpenCodePlugin(from: config)
            try AgentHookManager.writeConfig(config, for: agent)

            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/opencode/plugins/opencode-ding")
            try? FileManager.default.removeItem(at: pluginDir)

            print("✓ \(agent.displayName) — plugin removed")

        default:
            let hadDingHooks = !AgentHookManager.detectDingHookEvents(in: config).isEmpty
            guard hadDingHooks else {
                print("✓ \(agent.displayName) — no ding hooks to remove")
                return
            }

            config = try AgentHookManager.uninstallHooks(from: config, for: agent)
            try AgentHookManager.writeConfig(config, for: agent)
            print("✓ \(agent.displayName) — hooks removed")
        }
    }

    // MARK: - Shell Hook

    private func uninstallShellHook() async throws {
        let shell = detectShell()
        let hookDir = hookDirectory()
        let hookFile = hookDir.appendingPathComponent("hook.\(shell)")
        let rcFile = rcFilePath(for: shell)

        // Remove hook script file
        if FileManager.default.fileExists(atPath: hookFile.path) {
            try FileManager.default.removeItem(at: hookFile)
            print("✓ Removed hook script: \(hookFile.path)")
        } else {
            print("Hook script not found: \(hookFile.path)")
        }

        // Remove source line from RC file
        if let rcContent = try? String(contentsOf: rcFile, encoding: .utf8) {
            let guardComment = "# Added by ding"
            if rcContent.contains(guardComment) {
                let lines = rcContent.components(separatedBy: "\n")
                var filteredLines: [String] = []
                var skipMode = false
                for line in lines {
                    if line.contains(guardComment) {
                        skipMode = true
                        continue
                    }
                    if skipMode {
                        if line.hasPrefix("source ") || line.hasPrefix("export DING_THRESHOLD") {
                            continue
                        }
                        skipMode = false
                    }
                    filteredLines.append(line)
                }
                let newContent = filteredLines.joined(separator: "\n")
                try newContent.write(to: rcFile, atomically: true, encoding: .utf8)
                print("✓ Removed hook source line from: \(rcFile.path)")
            } else {
                print("Hook source line not found in: \(rcFile.path)")
            }
        }

        print("")
        print("Shell hook uninstalled. Restart your shell to apply changes.")
    }

    // MARK: - Shell Helpers

    private func detectShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if shell.hasSuffix("bash") { return "bash" }
        return "zsh"
    }

    private func hookDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/ding")
    }

    private func rcFilePath(for shell: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if shell == "bash" {
            return home.appendingPathComponent(".bashrc")
        }
        return home.appendingPathComponent(".zshrc")
    }
}
