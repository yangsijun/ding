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
