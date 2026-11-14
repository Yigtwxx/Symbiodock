import ServiceManagement
import os

/// Symbiodock as a login item. The system owns the state; nothing is stored here.
@MainActor
enum LoginItem {
    private static let logger = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but switched off by the user in System Settings: only they can turn it on.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// On failure the item simply stays as it was; the menu shows the real status next time.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Changing the login item failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
