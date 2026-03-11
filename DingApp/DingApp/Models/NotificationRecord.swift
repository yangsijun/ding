import Foundation

struct NotificationRecord: Codable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    let status: String  // "success", "failure", "warning", "info"
    let timestamp: Date

    init(id: UUID = UUID(), title: String, body: String, status: String, timestamp: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.timestamp = timestamp
    }
}
