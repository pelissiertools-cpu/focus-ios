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
            return "Tasks scheduled for today appear here. Drag in main focus what matters most. Your main focus section is always visible on homeview."
        case .inbox:
            return "A quick landing spot for your tasks. Use the sort by function to personalize your workflow. You can schedule them, group them into a project or even make a quick list."
        case .upcoming:
            return "See clearly what's ahead. Browse by timeframe and schedule tasks in a click. You can plan tasks for a week or month giving you more breathing room than specific days."
        case .backlog:
            return "All your uncompleted tasks, projects and quick lists in one place. Filter and search to find anything quickly."
        case .projects:
            return "Group related tasks into projects, create sections to help organize. Track progress and stay on top of larger goals."
        case .quickLists:
            return "Simple reusable checklists for your most common activities. Groceries, travel packing, returns. You can even schedule them."
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
