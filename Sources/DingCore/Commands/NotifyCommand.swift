import ArgumentParser
import Foundation

public struct NotifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a notification"
    )

    @Argument(help: "Notification title")
    var title: String

    @Argument(help: "Notification body")
    var body: String

    @Option(name: .shortAndLong, help: "Notification status")
    var status: String = "info"

    public init() {}
    public func run() async throws {
        print("not implemented")
    }
}
