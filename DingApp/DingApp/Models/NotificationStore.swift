import Foundation
import UserNotifications

@MainActor
class NotificationStore: ObservableObject {
    @Published private(set) var records: [NotificationRecord] = []

    private let maxRecords = 50
    private let userDefaultsKey = "ding_notification_records"

    init() {
        load()
    }

    func add(title: String, body: String, status: String) {
        let record = NotificationRecord(title: title, body: body, status: status)
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func clearAll() {
        records = []
        save()
    }

    func delete(record: NotificationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Sync delivered notifications from notification center (catches background arrivals)
    func syncDeliveredNotifications() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        var added = false
        for notification in delivered {
            let userInfo = notification.request.content.userInfo
            let date = notification.date

            // Skip if we already have a record at this exact timestamp
            let alreadyExists = records.contains { abs($0.timestamp.timeIntervalSince(date)) < 1 }
            if alreadyExists { continue }

            let title: String
            let body: String
            let status: String

            if let dingPayload = userInfo["ding"] as? [String: Any] {
                title = dingPayload["title"] as? String ?? notification.request.content.title
                body = dingPayload["body"] as? String ?? notification.request.content.body
                status = dingPayload["status"] as? String ?? "info"
            } else {
                title = notification.request.content.title
                body = notification.request.content.body
                status = "info"
            }

            let record = NotificationRecord(title: title, body: body, status: status, timestamp: date)
            records.insert(record, at: 0)
            added = true
        }

        if added {
            records.sort { $0.timestamp > $1.timestamp }
            if records.count > maxRecords {
                records = Array(records.prefix(maxRecords))
            }
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([NotificationRecord].self, from: data) {
            records = loaded
        }
    }
}
