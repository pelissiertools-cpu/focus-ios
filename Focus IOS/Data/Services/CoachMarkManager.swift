//
//  CoachMarkManager.swift
//  Focus IOS
//

import Foundation
import Combine

enum CoachMarkSection: String, CaseIterable {
    case today
    case inbox
    case upcoming
    case backlog
    case projects
    case quickLists

    var storageKey: String {
        "coach_mark_dismissed_\(rawValue)"
    }

    var icon: String {
        switch self {
        case .today:      return "sun.max.fill"
        case .inbox:      return "tray.and.arrow.down.fill"
        case .upcoming:   return "calendar"
        case .backlog:    return "tray.full.fill"
        case .projects:   return "folder.fill"
        case .quickLists: return "checklist"
        }
    }

    var title: String {
        switch self {
        case .today:      return "Your Daily Focus"
        case .inbox:      return "Capture Everything"
        case .upcoming:   return "Plan Ahead"
        case .backlog:    return "Your Full Library"
        case .projects:   return "Organize with Projects"
        case .quickLists: return "Quick Lists"
        }
    }

    var description: String {
        switch self {
        case .today:
            return "Tasks scheduled for today appear here. Drag to reorder and focus on what matters most."
        case .inbox:
            return "A quick landing spot for new tasks. Triage them later into projects or schedule them."
        case .upcoming:
            return "See what's ahead. Browse by day, week, or month and schedule tasks for the future."
        case .backlog:
            return "All your unfinished tasks in one place. Filter and search to find anything."
        case .projects:
            return "Group related tasks into projects. Track progress and stay on top of larger goals."
        case .quickLists:
            return "Simple checklists for groceries, packing, or any quick to-do. No scheduling needed."
        }
    }
}

@MainActor
class CoachMarkManager: ObservableObject {
    static let shared = CoachMarkManager()

    @Published private var dismissedSections: Set<String>

    private init() {
        var dismissed = Set<String>()
        for section in CoachMarkSection.allCases {
            if UserDefaults.standard.bool(forKey: section.storageKey) {
                dismissed.insert(section.rawValue)
            }
        }
        self.dismissedSections = dismissed
    }

    func shouldShow(_ section: CoachMarkSection) -> Bool {
        !dismissedSections.contains(section.rawValue)
    }

    func dismiss(_ section: CoachMarkSection) {
        UserDefaults.standard.set(true, forKey: section.storageKey)
        dismissedSections.insert(section.rawValue)
    }

    func resetAll() {
        for section in CoachMarkSection.allCases {
            UserDefaults.standard.removeObject(forKey: section.storageKey)
        }
        dismissedSections.removeAll()
    }
}
