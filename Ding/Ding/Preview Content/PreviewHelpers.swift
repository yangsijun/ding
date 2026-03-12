#if DEBUG
import Foundation

extension NotificationRecord {
    static let sampleData: [NotificationRecord] = [
        NotificationRecord(
            title: "Build succeeded",
            body: "main branch — 42s",
            status: "success",
            timestamp: Date().addingTimeInterval(-60)
        ),
        NotificationRecord(
            title: "Build failed",
            body: "feature/auth — exit code 1",
            status: "failure",
            timestamp: Date().addingTimeInterval(-300)
        ),
        NotificationRecord(
            title: "Deploy warning",
            body: "staging — disk usage 89%",
            status: "warning",
            timestamp: Date().addingTimeInterval(-1800)
        ),
        NotificationRecord(
            title: "Test passed",
            body: "test suite completed — 128 tests",
            status: "success",
            timestamp: Date().addingTimeInterval(-3600)
        ),
        NotificationRecord(
            title: "CI pipeline",
            body: "Pipeline #4521 started",
            status: "info",
            timestamp: Date().addingTimeInterval(-7200)
        ),
        NotificationRecord(
            title: "Deploy succeeded",
            body: "production v2.1.0 — 3m 12s",
            status: "success",
            timestamp: Date().addingTimeInterval(-86400)
        ),
        NotificationRecord(
            title: "Test failed",
            body: "3 tests failed in AuthTests",
            status: "failure",
            timestamp: Date().addingTimeInterval(-86400 - 1800)
        ),
        NotificationRecord(
            title: "Build succeeded",
            body: "hotfix/crash-fix — 18s",
            status: "success",
            timestamp: Date().addingTimeInterval(-86400 - 3600)
        ),
    ]
}
#endif
