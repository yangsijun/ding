import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tokenStore: TokenStore
    @EnvironmentObject var notificationStore: NotificationStore
    @StateObject private var permissionManager = NotificationPermissionManager()
    @State private var copied = false

    var body: some View {
        TabView {
            tokenTab
                .tabItem {
                    Label("Token", systemImage: "key.fill")
                }

            NotificationListView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
        }
        .task {
            await permissionManager.checkStatus()
        }
    }

    // MARK: - Token Tab

    private var tokenTab: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                if !tokenStore.deviceToken.isEmpty {
                    tokenReceivedView
                } else if let error = tokenStore.registrationError {
                    errorView(error: error)
                } else if permissionManager.authorizationStatus == .denied {
                    deniedView
                } else {
                    requestPermissionView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("ding")
        }
    }

    // MARK: - Token Received

    private var tokenReceivedView: some View {
        VStack(spacing: 16) {
            Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)

            QRCodeView(token: tokenStore.deviceToken)

            Text(tokenStore.deviceToken)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .lineLimit(3)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = tokenStore.deviceToken
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy Token",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderedProminent)

                ShareLink(
                    item: tokenStore.deviceToken,
                    subject: Text("ding Device Token")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Error State

    private func errorView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Registration Failed")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                permissionManager.openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Permission Denied

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Notifications Denied")
                .font(.headline)

            Text("Enable notifications in Settings to receive alerts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                permissionManager.openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Request Permission

    private var requestPermissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Button {
                Task {
                    await permissionManager.requestPermission()
                }
            } label: {
                Text("Tap to grant notification permission")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TokenStore())
        .environmentObject(NotificationStore())
}
