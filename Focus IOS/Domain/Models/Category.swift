//
//  Category.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a user-defined category for organizing tasks
/// Maps to the categories table in Supabase
struct Category: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var sortOrder: Int
    var type: TaskType
    let createdDate: Date
    var isSystem: Bool

    /// Well-known name for the Someday system category
    static let somedayName = "Someday"

    // Coding keys to match Supabase snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case sortOrder = "sort_order"
        case type
        case createdDate = "created_date"
        case isSystem = "is_system"
    }

    /// Initializer for creating new categories
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        sortOrder: Int = 0,
        type: TaskType = .task,
        createdDate: Date = Date(),
        isSystem: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.sortOrder = sortOrder
        self.type = type
        self.createdDate = createdDate
        self.isSystem = isSystem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        type = try container.decode(TaskType.self, forKey: .type)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }
}
