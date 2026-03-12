import ArgumentParser
import Foundation

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check ding configuration and relay connectivity"
    )

    public init() {}

    // ANSI color helpers
    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let reset = "\u{001B}[0m"
    private static let bold = "\u{001B}[1m"

    private static func ok(_ text: String) -> String { "\(green)✓\(reset) \(text)" }
    private static func fail(_ text: String) -> String { "\(red)✗\(reset) \(text)" }

    public func run() async throws {
        print("\(Self.bold)ding status\(Self.reset)")
        print("===========")
        print("")

        // Check device token
        let tokenOK: Bool
        do {
            let token = try KeychainService.getDeviceToken()
            let masked = String(token.prefix(8)) + "..." + String(token.suffix(8))
            print("Device token: \(Self.ok("Stored (\(masked))"))")
            tokenOK = true
        } catch {
            print("Device token: \(Self.fail("Not configured"))")
            tokenOK = false
        }

        // Check API key
        let keyOK: Bool
        do {
            _ = try KeychainService.getAPIKey()
            print("API key:      \(Self.ok("Stored"))")
            keyOK = true
        } catch {
            print("API key:      \(Self.fail("Not configured"))")
            keyOK = false
        }

        // CLI version

        // Show CLI version
        print("CLI version:  \(Config.version)")

        // Show last send timestamp
        if let lastSend = UserDefaults.standard.object(forKey: "ding_last_send") as? Date {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: lastSend, relativeTo: Date())
            print("Last sent:    \(Self.ok(relative))")
        } else {
            print("Last sent:    (never)")
        }

        // Check shell hook
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hookFile = home.appendingPathComponent(".config/ding/hook.zsh")
        let rcFile = home.appendingPathComponent(".zshrc")
        if FileManager.default.fileExists(atPath: hookFile.path) {
            // Read threshold from .zshrc
            let rcContent = (try? String(contentsOf: rcFile, encoding: .utf8)) ?? ""
            let thresholdValue: String
            if let line = rcContent.components(separatedBy: "\n")
                .first(where: { $0.hasPrefix("export DING_THRESHOLD=") }) {
                thresholdValue = String(line.dropFirst("export DING_THRESHOLD=".count)) + "s"
            } else {
                thresholdValue = "30s (default)"
            }
            print("Shell hook:   \(Self.ok("Installed (threshold: \(thresholdValue))"))")
        } else {
            print("Shell hook:   \(Self.fail("Not installed — run `ding install-hook`"))")
        }

        // Check relay connectivity
        print("")
        print("Checking relay connectivity...", terminator: " ")
        fflush(stdout)

        do {
            guard let url = URL(string: Config.relayURL + "/health") else {
                print(Self.fail("Invalid relay URL"))
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let version = json["version"] as? String {
                    print(Self.ok("v\(version)"))
                } else {
                    print(Self.ok("reachable"))
                }
            } else {
                print(Self.fail("Unexpected response"))
            }
        } catch {
            print(Self.fail(error.localizedDescription))
        }

        // Overall status
        print("")
        if tokenOK && keyOK {
            let readyMsg = Self.ok("Ready")
            print("Status: \(readyMsg)")
        } else {
            let notConfigMsg = Self.fail("Not configured — run `ding setup <token>` first")
            print("Status: \(notConfigMsg)")
        }
    }
}
