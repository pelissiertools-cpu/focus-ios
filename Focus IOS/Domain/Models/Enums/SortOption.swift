//
//  SortOption.swift
//  Focus IOS
//

import Foundation

enum SortOption: String, CaseIterable {
    case creationDate
    case priority
    case dueDate

    var displayName: String {
        switch self {
        case .dueDate: return "Due date"
        case .creationDate: return "Creation date"
        case .priority: return "Priority"
        }
    }

    /// Default direction when switching to this sort option
    var defaultDirection: SortDirection {
        switch self {
        case .dueDate: return .lowestFirst      // earliest first
        case .creationDate: return .highestFirst // newest first
        case .priority: return .highestFirst     // highest first
        }
    }

    /// Direction options in preferred display order for this sort option
    var directionOrder: [SortDirection] {
        switch self {
        case .dueDate: return [.lowestFirst, .highestFirst]
        default: return [.highestFirst, .lowestFirst]
        }
    }
}

enum SortDirection: String, CaseIterable {
    case highestFirst
    case lowestFirst

    func displayName(for option: SortOption) -> String {
        switch option {
        case .priority:
            return self == .highestFirst ? "Highest first" : "Lowest first"
        case .dueDate:
            return self == .highestFirst ? "Latest first" : "Earliest first"
        case .creationDate:
            return self == .highestFirst ? "Newest first" : "Oldest first"
        }
    }
}
