import ArgumentParser
import Foundation
import Darwin
var gChildPid: pid_t = 0

public struct WaitCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Run a command and notify on completion"
    )

    @Argument(parsing: .captureForPassthrough, help: "Command to execute (after --)")
    var command: [String] = []

    @Option(name: .shortAndLong, help: "Custom notification title")
    var title: String?

    public init() {}

    public func run() async throws {
        guard !command.isEmpty else {
            throw ValidationError("No command specified. Usage: ding wait -- <command>")
        }

        let startTime = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.environment = ProcessInfo.processInfo.environment

        // Ignore SIGINT in parent, forward to child
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        try process.run()

        let childPid = process.processIdentifier
        gChildPid = childPid
        signal(SIGINT) { _ in kill(gChildPid, SIGINT) }
        signal(SIGTERM) { _ in kill(gChildPid, SIGTERM) }

        process.waitUntilExit()

        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startTime)
        let commandName = command.first ?? "command"

        let status: NotificationPayload.Status = exitCode == 0 ? .success : .failure
        let notifTitle = title ?? (exitCode == 0 ? "✓ \(commandName)" : "✗ \(commandName)")
        let durationStr = formatDuration(duration)
        let body = exitCode == 0
            ? "Completed in \(durationStr)"
            : "Failed (exit \(exitCode)) in \(durationStr)"

        let payload = NotificationPayload(
            title: notifTitle,
            body: body,
            status: status,
            command: commandName,
            exitCode: Int(exitCode),
            duration: duration
        )

        do {
            try await RelayClient.send(payload)
        } catch {
            fputs("⚠️  Notification failed: \(error.localizedDescription)\n", stderr)
        }

        throw ExitCode(exitCode)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}
