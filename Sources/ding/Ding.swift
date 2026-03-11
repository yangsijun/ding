import ArgumentParser
import DingCore
import DingCore

@main
struct Ding: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ding",
        abstract: "Send notifications to Apple Watch via Ding",
        version: "0.1.0",
        subcommands: [
            WaitCommand.self,
            NotifyCommand.self,
            SetupCommand.self,
            StatusCommand.self,
            TestCommand.self,
        ]
    )
}
