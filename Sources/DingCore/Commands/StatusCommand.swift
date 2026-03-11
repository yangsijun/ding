import ArgumentParser
import Foundation

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check ding configuration and relay connectivity"
    )

    public init() {}

    public func run() async throws {
        print("ding status")
        print("===========")
        print("")

        // Check device token
        let tokenStatus: String
        do {
            let token = try KeychainService.getDeviceToken()
            let masked = String(token.prefix(8)) + "..." + String(token.suffix(8))
            tokenStatus = "✓ Stored (\(masked))"
        } catch {
            tokenStatus = "✗ Not configured"
        }
        print("Device token: \(tokenStatus)")

        // Check API key
        let keyStatus: String
        do {
            _ = try KeychainService.getAPIKey()
            keyStatus = "✓ Stored"
        } catch {
            keyStatus = "✗ Not configured"
        }
        print("API key:      \(keyStatus)")

        // Check relay URL
        print("Relay URL:    \(Config.relayURL)")

        // Check relay connectivity
        print("")
        print("Checking relay connectivity...", terminator: " ")
        fflush(stdout)

        do {
            guard let url = URL(string: Config.relayURL + "/health") else {
                print("✗ Invalid relay URL")
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    print("✓ \(status)")
                } else {
                    print("✓ reachable")
                }
            } else {
                print("✗ Unexpected response")
            }
        } catch {
            print("✗ \(error.localizedDescription)")
        }

        // Overall status
        print("")
        let tokenOK = (try? KeychainService.getDeviceToken()) != nil
        let keyOK = (try? KeychainService.getAPIKey()) != nil
        if tokenOK && keyOK {
            print("Status: ✓ Ready")
        } else {
            print("Status: ✗ Not configured — run `ding setup <token>` first")
        }
    }
}
