import Foundation

enum Config {
    // MARK: - Relay Configuration
    /// Cloudflare Worker relay URL for sending notifications
    static let relayURL = "https://ding-relay.example.com"

    // MARK: - Version
    static let version = "0.1.0"

    // MARK: - Keychain Configuration
    static let keychainService = "dev.sijun.ding"
    static let keychainAccount = "ding-credentials"
}
