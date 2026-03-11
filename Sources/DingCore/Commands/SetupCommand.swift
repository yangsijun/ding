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
        print("")
        print("Next steps:")
        print("  1. Set RELAY_SECRET=\(key) in your Cloudflare Worker secrets")
        print("  2. Set DEVICE_TOKEN=\(deviceToken) in your Cloudflare Worker secrets")
        print("  3. Run `ding test` to verify the connection")
    }

    private func generateAPIKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
