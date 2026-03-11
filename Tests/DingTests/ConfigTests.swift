import Testing
@testable import DingCore

@Suite("Config Tests")
struct ConfigTests {
    @Test("Relay URL is non-empty")
    func relayURLNonEmpty() {
        #expect(!Config.relayURL.isEmpty)
    }

    @Test("Version is non-empty")
    func versionNonEmpty() {
        #expect(!Config.version.isEmpty)
    }

    @Test("Keychain service is non-empty")
    func keychainServiceNonEmpty() {
        #expect(!Config.keychainService.isEmpty)
    }
}
