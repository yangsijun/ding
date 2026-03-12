import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
class NotificationPermissionManager: ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    #if DEBUG
    private var _isPreview = false
    #endif
    func checkStatus() async {
        #if DEBUG
        if _isPreview { return }
        #endif
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
        #if DEBUG
        if _isPreview { return }
        #endif
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
extension NotificationPermissionManager {
    static func preview(status: UNAuthorizationStatus = .authorized) -> NotificationPermissionManager {
        let manager = NotificationPermissionManager()
        manager.authorizationStatus = status
        manager._isPreview = true
        return manager
    }
}
#endif
