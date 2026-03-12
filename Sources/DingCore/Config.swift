import Foundation

enum Config {
    // MARK: - Relay Configuration
    /// Cloudflare Worker relay URL for sending notifications
    static let relayURL = "https://ding-relay.sijun0905.workers.dev"

    // MARK: - Version
    static let version = "0.1.0"

    // MARK: - Keychain Configuration
    static let keychainService = "dev.sijun.ding"
    static let keychainAccount = "ding-credentials"
}
