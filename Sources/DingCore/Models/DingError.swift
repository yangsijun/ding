import Foundation

enum DingError: LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case encodingError(String)
    case decodingError(String)
    case commandFailed(String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
