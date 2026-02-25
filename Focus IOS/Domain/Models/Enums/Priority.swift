//
//  Priority.swift
//  Focus IOS
//

import Foundation
import SwiftUI

/// Represents task priority levels
enum Priority: String, Codable, CaseIterable {
    case focus = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var sortIndex: Int {
        switch self {
        case .focus: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    var dotColor: Color {
        switch self {
        case .focus: return .appRed
        case .medium: return .priorityOrange
        case .low: return .priorityYellow
        }
    }
}
