import WatchKit
import UserNotifications
import os

class ExtensionDelegate: NSObject, ObservableObject, WKApplicationDelegate {
    private let logger = Logger(subsystem: "dev.sijun.ding.watch", category: "ExtensionDelegate")
    private let hapticManager = HapticManager()

    @Published var receivedNotifications: [(title: String, body: String, status: String, timestamp: Date)] = []

    func applicationDidFinishLaunching() {
        requestNotificationPermissions()
        logger.info("DingWatch app launched")
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            self.logger.info("Watch notification permission: \(granted)")
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
