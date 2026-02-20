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
}

enum SortDirection: String, CaseIterable {
    case highestFirst
    case lowestFirst

    var displayName: String {
        switch self {
        case .highestFirst: return "Highest first"
        case .lowestFirst: return "Lowest first"
        }
    }
}
