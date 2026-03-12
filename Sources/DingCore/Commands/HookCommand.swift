import ArgumentParser

public struct HookCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hook",
        abstract: "Manage notification hooks (shell and AI coding tools)",
        subcommands: [
            HookInstallCommand.self,
            HookUninstallCommand.self,
            HookStatusCommand.self,
        ]
    )

    public init() {}
}
