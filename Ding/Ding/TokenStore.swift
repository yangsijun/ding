import Foundation
import Combine

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

#if DEBUG
extension TokenStore {
    static func preview(
        token: String = "a1b2c3d4e5f67890abcdef1234567890a1b2c3d4e5f67890abcdef1234567890",
        error: String? = nil
    ) -> TokenStore {
        let store = TokenStore()
        store.deviceToken = token
        store.registrationError = error
        return store
    }
}
#endif
