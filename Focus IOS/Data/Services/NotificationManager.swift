//
//  NotificationManager.swift
//  Focus IOS
//

import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private static let storageKey = "notifications_enabled"

    /// Prevents re-entrant didSet when syncing state
    private var isSyncing = false

    /// Set when user tried to enable but was sent to iOS Settings
    private var pendingSystemEnable = false

    @Published var isEnabled: Bool {
        didSet {
            guard !isSyncing else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            if !isEnabled {
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

    /// Refreshes systemAuthorized from iOS settings. Syncs isEnabled accordingly.
    func checkSystemAuthorization() {
        _Concurrency.Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authorized = settings.authorizationStatus == .authorized
            self.systemAuthorized = authorized

            if authorized && pendingSystemEnable {
                // User returned from Settings after enabling — complete the toggle
                pendingSystemEnable = false
                self.isEnabled = true
            } else if !authorized && self.isEnabled {
                // System revoked permission — sync in-app state
                self.isSyncing = true
                self.isEnabled = false
                UserDefaults.standard.set(false, forKey: Self.storageKey)
                self.isSyncing = false
            }
        }
    }

    /// Request system notification permission. Returns true if granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            self.systemAuthorized = granted
            if granted {
                self.isEnabled = true
            }
            return granted
        } catch {
            return false
        }
    }

    /// Enable notifications with proper system permission handling.
    /// If .notDetermined, shows the native iOS "Allow Notifications?" dialog.
    /// If .denied, opens iOS Settings so the user can re-enable manually.
    /// Returns true if notifications were enabled.
    @discardableResult
    func enableNotifications() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        print("[NotificationManager] authorization status: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .notDetermined:
            return await requestPermission()
        case .denied:
            pendingSystemEnable = true
            openAppSettings()
            return false
        case .authorized, .provisional, .ephemeral:
            self.systemAuthorized = true
            self.isEnabled = true
            return true
        @unknown default:
            return false
        }
    }

    /// Disable notifications and remove all pending requests.
    func disableNotifications() {
        isEnabled = false
    }

    /// Opens the app's page in iOS Settings.
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
