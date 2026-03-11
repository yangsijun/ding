import Foundation

/// Shared notification payload exchanged between Mac, iPhone, and Watch
struct NotificationPayload: Codable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case success
        case failure
        case warning
        case info
    }

    let id: UUID
    let title: String
    let body: String
    let status: Status
    let timestamp: Date
    let command: String?
    let exitCode: Int?
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        status: Status,
        timestamp: Date = Date(),
        command: String? = nil,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.timestamp = timestamp
        self.command = command
        self.exitCode = exitCode
        self.duration = duration
    }

    /// Encode to JSON Data for transmission
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decode from JSON Data
    static func decode(from data: Data) throws -> NotificationPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NotificationPayload.self, from: data)
    }

    /// Convert to dictionary for WatchConnectivity
    func toDictionary() throws -> [String: Any] {
        let data = try encode()
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "NotificationPayload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert to dictionary"]
            )
        }
        return dict
    }

    /// Create from dictionary (WatchConnectivity)
    static func fromDictionary(_ dict: [String: Any]) throws -> NotificationPayload {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decode(from: data)
    }
}
