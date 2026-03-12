import WatchKit
import os

struct HapticManager {
    private let logger = Logger(subsystem: "dev.sijun.ding.watch", category: "HapticManager")

    func play(forStatus status: String) {
        let hapticType: WKHapticType
        switch status {
        case "success":
            hapticType = .success
        case "failure":
            hapticType = .failure
        case "warning":
            hapticType = .retry
        default:  // "info" and unknown
            hapticType = .notification
        }
        WKInterfaceDevice.current().play(hapticType)
        logger.info("Played haptic: \(String(describing: hapticType)) for status: \(status)")
    }
}
