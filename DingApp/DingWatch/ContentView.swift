import SwiftUI

struct ContentView: View {
    @EnvironmentObject var extensionDelegate: ExtensionDelegate

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("ding")
                .font(.headline)
            Text("Waiting for notifications...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
