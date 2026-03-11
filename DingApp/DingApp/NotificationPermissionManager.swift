import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationPermissionManager: ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await checkStatus()
        } catch {
            print("Permission request error: \(error)")
            await checkStatus()
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
