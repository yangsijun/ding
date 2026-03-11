import ArgumentParser
import Foundation

public struct SetupCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Configure Ding with APNs credentials"
    )

    @Option(name: .shortAndLong, help: "APNs key ID")
    var keyID: String?

    @Option(name: .shortAndLong, help: "APNs team ID")
    var teamID: String?

    public init() {}
    public func run() async throws {
        print("not implemented")
    }
}
