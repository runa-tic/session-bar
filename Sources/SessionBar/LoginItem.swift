import ServiceManagement

/// "Open at login", kept in the system's own list (System Settings › General › Login
/// Items) so it follows the app wherever it is installed and can be switched off there.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
