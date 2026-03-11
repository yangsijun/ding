import ArgumentParser
import Foundation

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check Ding configuration status"
    )

    public init() {}
    public func run() async throws {
        print("not implemented")
    }
}
