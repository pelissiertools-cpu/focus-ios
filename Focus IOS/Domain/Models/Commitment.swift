//
//  Commitment.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a commitment of a task to a specific timeframe and section
/// Maps to the commitments table in Supabase
struct Commitment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let taskId: UUID
    var timeframe: Timeframe
    var section: Section
    var commitmentDate: Date
    var sortOrder: Int
    let createdDate: Date

    // Coding keys to match Supabase snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taskId = "task_id"
        case timeframe
        case section
        case commitmentDate = "commitment_date"
        case sortOrder = "sort_order"
        case createdDate = "created_date"
    }

    /// Initializer for creating new commitments
    init(
        id: UUID = UUID(),
        userId: UUID,
        taskId: UUID,
        timeframe: Timeframe,
        section: Section,
        commitmentDate: Date,
        sortOrder: Int = 0,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.taskId = taskId
        self.timeframe = timeframe
        self.section = section
        self.commitmentDate = commitmentDate
        self.sortOrder = sortOrder
        self.createdDate = createdDate
    }
}
