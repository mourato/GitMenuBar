//
//  LoginItemManager.swift
//  GitMenuBar
//

import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
class LoginItemManager {
    var isEnabled: Bool = false

    private let loginItemIdentifier = "com.mourato.GitMenuBar"

    init() {
        checkLoginItemStatus()
    }

    func checkLoginItemStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") login item: \(error)")
        }
    }
}
