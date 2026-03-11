import SwiftUI

@main
struct DingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tokenStore = TokenStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tokenStore)
                .onAppear {
                    appDelegate.tokenStore = tokenStore
                }
        }
    }
}
