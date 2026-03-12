import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var tokenStore: TokenStore?
    var notificationStore: NotificationStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Check if permission was already granted (e.g. after onboarding)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    // MARK: - APNs Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            tokenStore?.update(token: token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            tokenStore?.registrationError = error.localizedDescription
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Parse ding payload and store notification record
        let userInfo = notification.request.content.userInfo
        if let dingPayload = userInfo["ding"] as? [String: Any] {
            let title = dingPayload["title"] as? String ?? notification.request.content.title
            let body = dingPayload["body"] as? String ?? notification.request.content.body
            let status = dingPayload["status"] as? String ?? "info"
            Task { @MainActor in
                self.notificationStore?.add(title: title, body: body, status: status)
            }
        } else {
            // Fallback: store from notification content directly
            let title = notification.request.content.title
            let body = notification.request.content.body
            Task { @MainActor in
                self.notificationStore?.add(title: title, body: body, status: "info")
            }
        }
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap (background/terminated → user tapped)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let dingPayload = userInfo["ding"] as? [String: Any] {
            let title = dingPayload["title"] as? String ?? response.notification.request.content.title
            let body = dingPayload["body"] as? String ?? response.notification.request.content.body
            let status = dingPayload["status"] as? String ?? "info"
            Task { @MainActor in
                self.notificationStore?.add(title: title, body: body, status: status)
            }
        } else {
            let title = response.notification.request.content.title
            let body = response.notification.request.content.body
            Task { @MainActor in
                self.notificationStore?.add(title: title, body: body, status: "info")
            }
        }
        completionHandler()
    }

    // Handle background/terminated notification receipt
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let dingPayload = userInfo["ding"] as? [String: Any] {
            let title = dingPayload["title"] as? String ?? ""
            let body = dingPayload["body"] as? String ?? ""
            let status = dingPayload["status"] as? String ?? "info"
            Task { @MainActor in
                self.notificationStore?.add(title: title, body: body, status: status)
            }
        }
        completionHandler(.newData)
    }
}
