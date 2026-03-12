import ArgumentParser
import Foundation
import Security

public struct SetupCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Configure ding with your device token"
    )

    @Argument(help: "APNs device token (64-character hex string from the iOS app)")
    var deviceToken: String

    @Option(name: .long, help: "Provide an existing API key instead of generating one")
    var apiKey: String?

    public init() {}

    public func run() async throws {
        // Validate token format: must be 64 hex characters
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard deviceToken.count == 64,
              deviceToken.unicodeScalars.allSatisfy({ hexChars.contains($0) }) else {
            throw ValidationError("Invalid device token. Must be a 64-character hexadecimal string.\nGet your token from the ding iOS app.")
        }

        // Generate or use provided API key
        let key: String
        if let provided = apiKey {
            key = provided
        } else {
            key = generateAPIKey()
        }

        // Store in Keychain
        try KeychainService.saveDeviceToken(deviceToken)
        try KeychainService.saveAPIKey(key)

        print("✓ Device token stored")
        print("✓ API key stored: \(key)")

        // Register device with relay
        do {
            try await registerWithRelay(deviceToken: deviceToken, apiKey: key)
            print("✓ Device registered with relay")
            print("")
            print("Run `ding test` to verify the connection.")
        } catch {
            print("⚠️  Relay registration failed: \(error.localizedDescription)")
            print("")
            print("You can retry with: ding setup \(deviceToken) --api-key \(key)")
        }
    }

    private func registerWithRelay(deviceToken: String, apiKey: String) async throws {
        guard let url = URL(string: Config.relayURL + "/register") else {
            throw DingError.networkError("Invalid relay URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["device_token": deviceToken])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DingError.networkError("Relay returned HTTP \(code)")
        }
    }

    private func generateAPIKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
