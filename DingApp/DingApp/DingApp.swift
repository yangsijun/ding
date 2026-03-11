import SwiftUI

@main
struct DingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var tokenStore = TokenStore()
    @StateObject private var notificationStore = NotificationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tokenStore)
                .environmentObject(notificationStore)
                .onAppear {
                    appDelegate.tokenStore = tokenStore
                    appDelegate.notificationStore = notificationStore
                }
        }
    }
}
