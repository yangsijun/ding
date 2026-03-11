import Foundation

public enum RelayClient {
    public static func send(_ payload: NotificationPayload) async throws {
        guard let url = URL(string: Config.relayURL + "/push") else {
            throw DingError.networkError("Invalid relay URL: \(Config.relayURL)")
        }

        let apiKey: String
        do {
            apiKey = try KeychainService.getAPIKey()
        } catch {
            throw DingError.configurationError("No API key stored. Run `ding setup <token>` first.")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try payload.encode()

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DingError.networkError("Relay returned HTTP \(code)")
        }

        // Store last successful send timestamp
        UserDefaults.standard.set(Date(), forKey: "ding_last_send")
    }
}
