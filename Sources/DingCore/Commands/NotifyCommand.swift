import ArgumentParser
import Foundation

public struct NotifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a custom notification"
    )

    @Argument(help: "Notification message body")
    var message: String

    @Option(name: .shortAndLong, help: "Notification title (default: ding)")
    var title: String = "ding"

    @Option(name: .shortAndLong, help: "Status: success, failure, warning, info")
    var status: String = "info"

    public init() {}

    public func run() async throws {
        let notifStatus = NotificationPayload.Status(rawValue: status) ?? .info
        let payload = NotificationPayload(
            title: title,
            body: message,
            status: notifStatus
        )
        do {
            try await RelayClient.send(payload)
            print("✓ Notification sent")
        } catch {
            fputs("✗ Failed to send notification: \(error.localizedDescription)\n", stderr)
            throw ExitCode(1)
        }
    }
}
