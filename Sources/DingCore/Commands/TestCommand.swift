import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Send a test notification"
    )

    @Option(name: .shortAndLong, help: "Test notification status")
    var status: String = "info"

    public init() {}
    public func run() async throws {
        print("not implemented")
    }
}
