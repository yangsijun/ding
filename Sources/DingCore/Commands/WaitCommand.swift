import ArgumentParser
import Foundation

public struct WaitCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Run a command and notify on completion"
    )

    @Argument(parsing: .captureForPassthrough, help: "Command to execute")
    var command: [String]

    @Option(name: .shortAndLong, help: "Custom notification title")
    var title: String?

    public init() {}
    public func run() async throws {
        print("not implemented")
    }
}
