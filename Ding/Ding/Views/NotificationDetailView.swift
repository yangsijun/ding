import SwiftUI

struct NotificationDetailView: View {
    let record: NotificationRecord
    
    var body: some View {
        List {
            Section("Content") {
                LabeledContent("Title", value: record.title)
                LabeledContent("Body", value: record.body)
            }
            Section("Metadata") {
                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(statusColor(record.status))
                            .frame(width: 10, height: 10)
                        Text(record.status.capitalized)
                    }
                }
                LabeledContent("Received", value: record.timestamp.formatted(.dateTime.month().day().year().hour().minute().second()))
            }
        }
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview("Success") {
    NavigationView {
        NotificationDetailView(record: NotificationRecord(title: "Build succeeded", body: "main branch — 42s", status: "success"))
    }
}

#Preview("Failure") {
    NavigationView {
        NotificationDetailView(record: NotificationRecord(title: "Build failed", body: "feature/auth — exit code 1", status: "failure"))
    }
}

#Preview("Warning") {
    NavigationView {
        NotificationDetailView(record: NotificationRecord(title: "Deploy warning", body: "staging — disk usage 89%", status: "warning"))
    }
}

#Preview("Info") {
    NavigationView {
        NotificationDetailView(record: NotificationRecord(title: "CI pipeline", body: "Pipeline #4521 started", status: "info"))
    }
}
