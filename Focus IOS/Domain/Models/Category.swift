//
//  Category.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a user-defined category for organizing tasks
/// Maps to the categories table in Supabase
struct Category: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String
    var sortOrder: Int
    var type: String
    let createdDate: Date

    // Coding keys to match Supabase snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case sortOrder = "sort_order"
        case type
        case createdDate = "created_date"
    }

    /// Initializer for creating new categories
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        sortOrder: Int = 0,
        type: String = "task",
        createdDate: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.sortOrder = sortOrder
        self.type = type
        self.createdDate = createdDate
    }
}
