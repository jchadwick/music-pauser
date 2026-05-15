import ServiceManagement

final class LoginItem {
    static func register() {
        do {
            if SMAppService.mainApp.status == .enabled { return }
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register login item: \(error)")
        }
    }
    
    static func unregister() {
        do {
            if SMAppService.mainApp.status == .notRegistered { return }
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to unregister login item: \(error)")
        }
    }
}
