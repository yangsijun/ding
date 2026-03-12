import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tokenStore: TokenStore
    @EnvironmentObject var notificationStore: NotificationStore
    @StateObject private var permissionManager = NotificationPermissionManager()
    @State private var copied = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

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
        .fullScreenCover(isPresented: $showOnboarding) {
            NotificationOnBoarding {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showOnboarding = false
            }
        }
        .task {
            await permissionManager.checkStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await permissionManager.checkStatus()
                await notificationStore.syncDeliveredNotifications()
            }
        }
    }
    private var tokenTab: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Permission warning banner
                    if permissionManager.authorizationStatus == .denied {
                        permissionWarningBanner
                    }

                    if !tokenStore.deviceToken.isEmpty {
                        tokenReceivedView
                    } else if let error = tokenStore.registrationError {
                        errorView(error: error)
                    } else if permissionManager.authorizationStatus == .denied {
                        deniedView
                    } else {
                        awaitingTokenView
                    }
                }
                .padding()
            }
            .navigationTitle("ding")
        }
    }

    // MARK: - Token Received

    private var tokenReceivedView: some View {
        VStack(spacing: 20) {
            Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)

            // Token display
            Text(tokenStore.deviceToken)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .lineLimit(3)

            // Copy / Share
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

            // Setup guide
            setupGuideView
        }
    }

    private var setupGuideView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup")
                .font(.headline)

            guideStep(number: 1, text: "Install ding CLI")
            codeBlock("brew install sijun/tap/ding")

            guideStep(number: 2, text: "Copy the token above and run:")
            codeBlock("ding setup <token>")

            guideStep(number: 3, text: "Verify the connection:")
            codeBlock("ding test")

            guideStep(number: 4, text: "Auto-notify on long commands:")
            codeBlock("ding install-hook")
            Text("Commands over 30s will trigger a notification.\nCustomize with: ding install-hook -t 10")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray5))
            .cornerRadius(6)
            .padding(.leading, 28)
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

    // MARK: - Awaiting Token

    private var awaitingTokenView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Waiting for Token")
                .font(.headline)

            Text("Notification permission granted.\nDevice token will appear shortly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Permission Warning Banner

    private var permissionWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications Disabled")
                    .font(.subheadline.weight(.semibold))
                Text("You won't receive alerts until notifications are enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                permissionManager.openSettings()
            } label: {
                Text("Settings")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(.systemOrange).opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(TokenStore())
        .environmentObject(NotificationStore())
}
