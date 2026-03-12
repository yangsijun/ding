import Foundation
import UserNotifications

@MainActor
class NotificationStore: ObservableObject {
    @Published private(set) var records: [NotificationRecord] = []
    @Published var saveEnabled: Bool {
        didSet {
            sharedDefaults?.set(saveEnabled, forKey: saveEnabledKey)
        }
    }

    private let maxRecords = 50
    private let recordsKey = "ding_notification_records"
    private let saveEnabledKey = "ding_save_notifications_enabled"
    private static let appGroupID = "group.dev.sijun.ding"

    private let sharedDefaults: UserDefaults?

    init() {
        self.sharedDefaults = UserDefaults(suiteName: Self.appGroupID)
        self.saveEnabled = sharedDefaults?.object(forKey: saveEnabledKey) as? Bool ?? true
        load()
        migrateFromStandardDefaults()
    }

    func add(title: String, body: String, status: String) {
        guard saveEnabled else { return }
        let record = NotificationRecord(title: title, body: body, status: status)

        // Deduplicate: skip if same title+body within 2 seconds
        if let latest = records.first,
           latest.title == record.title,
           latest.body == record.body,
           abs(latest.timestamp.timeIntervalSince(record.timestamp)) < 2 {
            return
        }

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

    /// Load records from shared storage (includes NSE-saved records)
    func reloadFromSharedStorage() {
        load()
    }

    /// Sync delivered notifications from notification center (catches background arrivals)
    func syncDeliveredNotifications() async {
        // First, reload from shared storage (NSE may have saved new records)
        load()

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

    // MARK: - Persistence (shared App Group UserDefaults)

    private func save() {
        let dicts: [[String: String]] = records.map { record in
            [
                "id": record.id.uuidString,
                "title": record.title,
                "body": record.body,
                "status": record.status,
                "timestamp": ISO8601DateFormatter().string(from: record.timestamp)
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dicts) {
            sharedDefaults?.set(data, forKey: recordsKey)
        }
    }

    private func load() {
        guard let data = sharedDefaults?.data(forKey: recordsKey),
              let dicts = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return
        }

        let formatter = ISO8601DateFormatter()
        records = dicts.compactMap { dict in
            guard let idStr = dict["id"], let id = UUID(uuidString: idStr),
                  let title = dict["title"],
                  let body = dict["body"],
                  let status = dict["status"],
                  let tsStr = dict["timestamp"], let ts = formatter.date(from: tsStr) else {
                return nil
            }
            return NotificationRecord(id: id, title: title, body: body, status: status, timestamp: ts)
        }
    }

    /// One-time migration from standard UserDefaults to shared App Group
    private func migrateFromStandardDefaults() {
        let oldKey = "ding_notification_records"
        guard let oldData = UserDefaults.standard.data(forKey: oldKey) else { return }

        // Try to decode old Codable format
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let oldRecords = try? decoder.decode([NotificationRecord].self, from: oldData) {
            // Merge: add old records that don't already exist
            let existingIDs = Set(records.map { $0.id })
            let newRecords = oldRecords.filter { !existingIDs.contains($0.id) }
            if !newRecords.isEmpty {
                records.append(contentsOf: newRecords)
                records.sort { $0.timestamp > $1.timestamp }
                if records.count > maxRecords {
                    records = Array(records.prefix(maxRecords))
                }
                save()
            }
        }

        // Remove old data
        UserDefaults.standard.removeObject(forKey: oldKey)
    }
}
