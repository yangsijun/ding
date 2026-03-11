import SwiftUI

@main
struct DingWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(extensionDelegate)
        }
    }
}
