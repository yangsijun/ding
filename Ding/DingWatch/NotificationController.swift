import WatchKit
import SwiftUI
import UserNotifications

class NotificationController: WKUserNotificationHostingController<NotificationContentView> {
    var notification: UNNotification?

    override var body: NotificationContentView {
        let status = notification?.request.content.userInfo["ding"] as? [String: Any]
        let statusStr = (status?["status"] as? String) ?? "info"
        return NotificationContentView(
            title: notification?.request.content.title ?? "ding",
            message: notification?.request.content.body ?? "",
            status: statusStr
        )
    }

    override func didReceive(_ notification: UNNotification) {
        self.notification = notification
        // Play haptic when notification arrives
        let status = notification.request.content.userInfo["ding"] as? [String: Any]
        let statusStr = (status?["status"] as? String) ?? "info"
        HapticManager().play(forStatus: statusStr)
    }
}

struct NotificationContentView: View {
    let title: String
    let message: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch status {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case "success": return .green
        case "failure": return .red
        case "warning": return .orange
        default: return .blue
        }
    }
}
