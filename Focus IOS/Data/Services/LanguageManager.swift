//
//  LanguageManager.swift
//  Focus IOS
//

import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let storageKey = "app_language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    var locale: Locale { Locale(identifier: currentLanguage.rawValue) }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           let language = AppLanguage(rawValue: stored) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .english
        }
    }
}
