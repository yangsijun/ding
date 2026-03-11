import Foundation

@MainActor
final class TokenStore: ObservableObject {
    @Published var deviceToken: String = ""
    @Published var registrationError: String? = nil

    init() {
        // Load from UserDefaults
        if let savedToken = UserDefaults.standard.string(forKey: "apns_device_token") {
            self.deviceToken = savedToken
        }
    }

    func update(token: String) {
        self.deviceToken = token
        UserDefaults.standard.set(token, forKey: "apns_device_token")
    }
}
