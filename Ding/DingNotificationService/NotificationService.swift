import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    private static let appGroupID = "group.dev.sijun.ding"
    private static let recordsKey = "ding_notification_records"
    private static let mutedKey = "notificationsMuted"
    private static let saveEnabledKey = "ding_save_notifications_enabled"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        // Save notification record to shared storage
        saveNotificationRecord(from: request.content.userInfo)

        // Check mute state — suppress banner/sound if muted
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        let isMuted = defaults?.bool(forKey: Self.mutedKey) ?? false

        if isMuted {
            // Deliver silently (no banner, no sound)
            let silentContent = bestAttemptContent ?? (request.content.mutableCopy() as! UNMutableNotificationContent)
            silentContent.sound = nil
            silentContent.interruptionLevel = .passive
            contentHandler(silentContent)
        } else {
            contentHandler(bestAttemptContent ?? request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Shared Storage

    private func saveNotificationRecord(from userInfo: [AnyHashable: Any]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }

        // Check if saving is enabled (default: true)
        let saveEnabled = defaults.object(forKey: Self.saveEnabledKey) as? Bool ?? true
        guard saveEnabled else { return }

        let title: String
        let body: String
        let status: String

        if let ding = userInfo["ding"] as? [String: Any] {
            title = ding["title"] as? String ?? ""
            body = ding["body"] as? String ?? ""
            status = ding["status"] as? String ?? "info"
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let alert = aps["alert"] as? [String: Any] {
            title = alert["title"] as? String ?? ""
            body = alert["body"] as? String ?? ""
            status = "info"
        } else {
            return
        }

        guard !title.isEmpty || !body.isEmpty else { return }

        let record: [String: String] = [
            "id": UUID().uuidString,
            "title": title,
            "body": body,
            "status": status,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        var records = loadRecords(from: defaults)
        records.insert(record, at: 0)

        // Cap at 50
        if records.count > 50 {
            records = Array(records.prefix(50))
        }

        if let data = try? JSONSerialization.data(withJSONObject: records) {
            defaults.set(data, forKey: Self.recordsKey)
        }
    }

    private func loadRecords(from defaults: UserDefaults) -> [[String: String]] {
        guard let data = defaults.data(forKey: Self.recordsKey),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        return records
    }
}
