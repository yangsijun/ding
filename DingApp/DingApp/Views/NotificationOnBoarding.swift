import SwiftUI
import UserNotifications

struct NotificationOnBoarding: View {
    var onComplete: () -> Void
    /// View Properties
    @State private var animateNotification: Bool = false
    @State private var loopContinues: Bool = true
    @State private var askPermission: Bool = false
    @State private var showArrow: Bool = false
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(backgroundColor)
                    .ignoresSafeArea()
                    .blurOpacity(askPermission)

                Image(systemName: "arrow.up")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(foregroundColor)
                    .offset(x: isiOS26 ? 75 : 70, y: 155)
                    .blurOpacity(showArrow)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                iPhonePreview()
                    .padding(.top, 15)

                VStack(spacing: 20) {
                    Text("Never Miss a\nFinished Task")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Get push notifications when your builds, tests, and deploys complete or fail.")
                        .font(.callout)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Button {
                        if authorization == .authorized {
                            onComplete()
                        } else if authorization == .denied {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            askNotificationPermission()
                        }
                    } label: {
                        Text(primaryButtonTitle)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(foregroundColor)
                            .frame(height: 55)
                            .background(backgroundColor, in: .rect(cornerRadius: 20))
                    }


                    if authorization == .notDetermined {
                        Button {
                            onComplete()
                        } label: {
                            Text("Skip for Now")
                                .fontWeight(.semibold)
                                .foregroundStyle(backgroundColor)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 20)
            }
            .blurOpacity(!askPermission)
        }
        .onDisappear { loopContinues = false }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorization = settings.authorizationStatus
        }
        .interactiveDismissDisabled()
    }

    private var primaryButtonTitle: String {
        switch authorization {
        case .authorized: "Get Started"
        case .denied: "Go to Settings"
        default: "Enable Notifications"
        }
    }

    // MARK: - iPhone Preview

    @ViewBuilder
    private func iPhonePreview() -> some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = min(size.height / 340, 1)
            let width: CGFloat = 320
            let cornerRadius: CGFloat = 30

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor.opacity(0.06))

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.gray.opacity(0.5), lineWidth: 1.5)

                // Mock widgets & apps
                VStack(spacing: 15) {
                    HStack(spacing: 15) {
                        RoundedRectangle(cornerRadius: 20)
                        RoundedRectangle(cornerRadius: 20)
                    }
                    .frame(height: 130)

                    LazyVGrid(columns: Array(repeating: GridItem(spacing: 15), count: 4), spacing: 15) {
                        ForEach(1...12, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .frame(height: 55)
                        }
                    }
                }
                .padding(20)
                .padding(.top, 20)
                .foregroundStyle(backgroundColor.opacity(0.1))

                // Status bar
                HStack(spacing: 4) {
                    Text("9:41")
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.50percent")
                }
                .font(.caption2)
                .padding(.horizontal, 20)
                .padding(.top, 15)

                // Notification
                notificationView()
            }
            .frame(width: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .mask {
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .clear, location: 0.9)
                ], startPoint: .top, endPoint: .bottom)
                .padding(-1)
            }
            .scaleEffect(scale, anchor: .top)
        }
    }

    @ViewBuilder
    private func notificationView() -> some View {
        HStack(alignment: .center, spacing: 8) {
            // App icon
            Image(systemName: "bell.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ding")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("Now")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                }

                Text("✓ Build succeeded — 42s")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .gray.opacity(0.5), radius: 1.5)
        .padding(.horizontal, 12)
        .padding(.top, 40)
        .offset(y: animateNotification ? 0 : -200)
        .clipped()
        .task {
            await loopAnimation()
        }
    }

    // MARK: - Animation

    private func loopAnimation() async {
        try? await Task.sleep(for: .seconds(0.5))

        withAnimation(.smooth(duration: 1)) {
            animateNotification = true
        }

        try? await Task.sleep(for: .seconds(4))

        withAnimation(.smooth(duration: 1)) {
            animateNotification = false
        }

        guard loopContinues else { return }
        try? await Task.sleep(for: .seconds(1.3))
        await loopAnimation()
    }

    // MARK: - Permission

    private func askNotificationPermission() {
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                askPermission = true
            }

            try? await Task.sleep(for: .seconds(0.3))

            withAnimation(.linear(duration: 0.3)) {
                showArrow = true
            }

            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }

            let settings = await UNUserNotificationCenter.current().notificationSettings()

            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                askPermission = false
                showArrow = false
                authorization = settings.authorizationStatus
            }
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundColor: Color {
        colorScheme != .dark ? .white : .black
    }
}

// MARK: - View Extensions

fileprivate extension View {
    @ViewBuilder
    func blurOpacity(_ status: Bool) -> some View {
        self
            .compositingGroup()
            .opacity(status ? 1 : 0)
            .blur(radius: status ? 0 : 10)
    }

    var isiOS26: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }
}

#Preview {
    NotificationOnBoarding {
        print("onboarding complete")
    }
}
