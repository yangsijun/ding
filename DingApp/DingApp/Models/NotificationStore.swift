import Foundation

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
