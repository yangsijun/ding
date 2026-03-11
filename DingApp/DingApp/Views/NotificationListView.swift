import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject var notificationStore: NotificationStore

    var body: some View {
        NavigationView {
            Group {
                if notificationStore.records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No notifications yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(notificationStore.records) { record in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(statusColor(record.status))
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(record.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(record.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if !notificationStore.records.isEmpty {
                    Button("Clear All") {
                        notificationStore.clearAll()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "failure": return .red
        case "warning": return .orange
        default: return .blue
        }
    }
}

#Preview {
    NotificationListView()
        .environmentObject(NotificationStore())
}
