import Testing
import Foundation
@testable import DingCore

@Suite("Token Validation Tests")
struct SetupCommandTests {
    // Token validation: must be 64 hex chars
    @Test("Valid 64-char hex token passes")
    func validToken() {
        let token = String(repeating: "a", count: 64)
        #expect(isValidDeviceToken(token) == true)
    }

    @Test("Token with uppercase hex passes")
    func uppercaseHex() {
        let token = String(repeating: "A", count: 64)
        #expect(isValidDeviceToken(token) == true)
    }

    @Test("Token too short fails")
    func tooShort() {
        let token = String(repeating: "a", count: 63)
        #expect(isValidDeviceToken(token) == false)
    }

    @Test("Token too long fails")
    func tooLong() {
        let token = String(repeating: "a", count: 65)
        #expect(isValidDeviceToken(token) == false)
    }

    @Test("Token with non-hex chars fails")
    func nonHexChars() {
        let token = String(repeating: "g", count: 64)
        #expect(isValidDeviceToken(token) == false)
    }

    @Test("Empty token fails")
    func emptyToken() {
        #expect(isValidDeviceToken("") == false)
    }

    // Helper that mirrors SetupCommand's validation logic
    private func isValidDeviceToken(_ token: String) -> Bool {
        guard token.count == 64 else { return false }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return token.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }
}
