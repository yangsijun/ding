import Testing
import Foundation
@testable import DingCore

@Suite("NotificationPayload Tests")
struct NotificationPayloadTests {
    @Test("Encodes and decodes roundtrip")
    func roundtrip() throws {
        let payload = NotificationPayload(
            title: "Build passed",
            body: "main branch",
            status: .success,
            command: "swift build",
            exitCode: 0,
            duration: 12.5
        )
        let data = try payload.encode()
        let decoded = try NotificationPayload.decode(from: data)
        #expect(decoded.title == payload.title)
        #expect(decoded.body == payload.body)
        #expect(decoded.status == payload.status)
        #expect(decoded.command == payload.command)
        #expect(decoded.exitCode == payload.exitCode)
    }

    @Test("All status types encode correctly")
    func allStatuses() throws {
        for status in NotificationPayload.Status.allCases {
            let payload = NotificationPayload(title: "test", body: "body", status: status)
            let data = try payload.encode()
            let decoded = try NotificationPayload.decode(from: data)
            #expect(decoded.status == status)
        }
    }

    @Test("Optional fields can be nil")
    func optionalFields() throws {
        let payload = NotificationPayload(title: "test", body: "body", status: .info)
        let data = try payload.encode()
        let decoded = try NotificationPayload.decode(from: data)
        #expect(decoded.command == nil)
        #expect(decoded.exitCode == nil)
        #expect(decoded.duration == nil)
    }
}
