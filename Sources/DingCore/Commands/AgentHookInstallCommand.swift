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
