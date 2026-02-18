//
//  AppearanceManager.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private static let storageKey = "app_appearance"

    @Published var currentAppearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(currentAppearance.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           let appearance = AppAppearance(rawValue: stored) {
            self.currentAppearance = appearance
        } else {
            self.currentAppearance = .system
        }
    }
}
