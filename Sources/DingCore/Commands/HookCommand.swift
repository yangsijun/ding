import ArgumentParser
import Foundation

public struct HookCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hook",
        abstract: "Handle AI tool hook events (reads context from stdin)"
    )

    @Option(name: .shortAndLong, help: "Source tool: claude, gemini")
    var source: String

    @Option(name: .shortAndLong, help: "Event name: Stop, Notification, AfterAgent, SessionEnd")
    var event: String

    public init() {}

    // MARK: - Stdin JSON structures

    /// Common fields shared across hook systems
    private struct HookInput: Decodable {
        let cwd: String?
        let hook_event_name: String?
        let prompt: String?
        let prompt_response: String?
        let notification_type: String?
        let message: String?

        // Claude Code fields
        let transcript_path: String?
    }

    // MARK: - Run

    public func run() async throws {
        let input = readStdinJSON()
        let projectName = extractProjectName(from: input)
        let (title, body, status) = formatNotification(input: input, projectName: projectName)

        let payload = NotificationPayload(
            title: title,
            body: body,
            status: status
        )

        do {
            try await RelayClient.send(payload)
        } catch {
            // Silent failure — hooks should never block the agent
        }
    }

    // MARK: - Helpers

    private func readStdinJSON() -> HookInput? {
        // Read all available stdin data (non-blocking)
        var data = Data()
        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        // Set stdin to non-blocking to avoid hanging if no data
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)

        while true {
            let bytesRead = read(STDIN_FILENO, buffer, bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        // Restore blocking mode
        fcntl(STDIN_FILENO, F_SETFL, flags)

        guard !data.isEmpty else { return nil }

        return try? JSONDecoder().decode(HookInput.self, from: data)
    }

    private func extractProjectName(from input: HookInput?) -> String {
        if let cwd = input?.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        // Fallback: use $CLAUDE_PROJECT_DIR or $GEMINI_PROJECT_DIR
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"]
            ?? ProcessInfo.processInfo.environment["GEMINI_PROJECT_DIR"] {
            return URL(fileURLWithPath: dir).lastPathComponent
        }
        return "Unknown"
    }

    private var sourceName: String {
        switch source.lowercased() {
        case "claude": return "Claude Code"
        case "gemini": return "Gemini CLI"
        default: return source
        }
    }

    private func formatNotification(input: HookInput?, projectName: String) -> (title: String, body: String, status: NotificationPayload.Status) {
        let title = "ding \u{00b7} \(sourceName)"
        let dirLine = input?.cwd ?? ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? ProcessInfo.processInfo.environment["GEMINI_PROJECT_DIR"] ?? ""

        switch event {
        case "Stop", "AfterAgent":
            let message = summarizeCompletion(input: input)
            let body = dirLine.isEmpty ? message : "\(dirLine)\n\(message)"
            return (title, body, .success)

        case "Notification":
            let message = input?.message ?? "Needs your attention"
            let body = dirLine.isEmpty ? message : "\(dirLine)\n\(message)"
            return (title, body, .warning)

        case "SessionEnd":
            let body = dirLine.isEmpty ? "Session ended" : "\(dirLine)\nSession ended"
            return (title, body, .info)

        default:
            let body = dirLine.isEmpty ? event : "\(dirLine)\n\(event)"
            return (title, body, .info)
        }
    }

    private func summarizeCompletion(input: HookInput?) -> String {
        // Try to extract a useful summary from the prompt
        if let prompt = input?.prompt, !prompt.isEmpty {
            let truncated = truncate(prompt, maxLength: 80)
            return "Done: \(truncated)"
        }
        return "Task completed"
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if cleaned.count <= maxLength {
            return cleaned
        }
        return String(cleaned.prefix(maxLength)) + "…"
    }
}
