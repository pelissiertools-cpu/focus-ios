//
//  NotificationManager.swift
//  Focus IOS
//

import Foundation
import Combine
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private static let storageKey = "notifications_enabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            if isEnabled {
                requestPermission()
            } else {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
    }

    /// Whether the system has granted notification permission
    @Published var systemAuthorized: Bool = false

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
        checkSystemAuthorization()
    }

    func checkSystemAuthorization() {
        let center = UNUserNotificationCenter.current()
        _Concurrency.Task { @MainActor in
            let settings = await center.notificationSettings()
            self.systemAuthorized = settings.authorizationStatus == .authorized
        }
    }

    private func requestPermission() {
        let center = UNUserNotificationCenter.current()
        _Concurrency.Task { @MainActor in
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                self.systemAuthorized = granted
                if !granted {
                    self.isEnabled = false
                }
            } catch {
                self.isEnabled = false
            }
        }
    }
}
