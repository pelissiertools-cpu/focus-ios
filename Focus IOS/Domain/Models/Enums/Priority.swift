//
//  Priority.swift
//  Focus IOS
//

import Foundation
import SwiftUI

/// Represents task priority levels
enum Priority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var sortIndex: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    var dotColor: Color {
        switch self {
        case .high: return .appRed
        case .medium: return .priorityOrange
        case .low: return .priorityBlue
        }
    }

    var containerColor: Color {
        switch self {
        case .high: return .appRed.opacity(0.08)
        case .medium: return .priorityOrange.opacity(0.08)
        case .low: return .priorityBlue.opacity(0.10)
        }
    }
}
