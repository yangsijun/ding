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
