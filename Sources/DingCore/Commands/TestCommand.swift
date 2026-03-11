import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Send 4 test notifications (success, failure, warning, info)"
    )

    @Option(name: .long, help: "Delay between notifications in seconds (default: 1.5)")
    var delay: Double = 1.5

    public init() {}

    public func run() async throws {
        let tests: [(NotificationPayload.Status, String)] = [
            (.success, "Test notification — Success"),
            (.failure, "Test notification — Failure"),
            (.warning, "Test notification — Warning"),
            (.info,    "Test notification — Info"),
        ]

        var sent = 0
        var failed = 0

        for (index, (status, body)) in tests.enumerated() {
            print("Sending \(index + 1)/\(tests.count)...", terminator: " ")
            fflush(stdout)

            let payload = NotificationPayload(
                title: "ding test",
                body: body,
                status: status
            )

            do {
                try await RelayClient.send(payload)
                print("✓")
                sent += 1
            } catch {
                print("✗ \(error.localizedDescription)")
                failed += 1
            }

            if index < tests.count - 1 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        print("")
        if failed == 0 {
            print("✓ \(sent)/\(tests.count) sent successfully")
        } else {
            print("⚠️  \(sent)/\(tests.count) sent, \(failed) failed")
            throw ExitCode(1)
        }
    }
}
