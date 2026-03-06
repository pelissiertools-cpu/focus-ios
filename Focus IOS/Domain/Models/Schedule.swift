//
//  Schedule.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a schedule of a task to a specific timeframe and section
/// Maps to the schedules table in Supabase
struct Schedule: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let taskId: UUID
    var timeframe: Timeframe
    var section: Section
    var scheduleDate: Date
    var sortOrder: Int
    let createdDate: Date

    /// Parent schedule ID for trickle-down hierarchy (Year → Month → Week → Day)
    var parentScheduleId: UUID?

    /// Scheduled time for calendar timeline display (nil = unscheduled)
    var scheduledTime: Date?

    /// Duration in minutes for calendar timeline display (defaults to 30)
    var durationMinutes: Int?

    // Coding keys to match Supabase snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taskId = "task_id"
        case timeframe
        case section
        case scheduleDate = "schedule_date"
        case sortOrder = "sort_order"
        case createdDate = "created_date"
        case parentScheduleId = "parent_schedule_id"
        case scheduledTime = "scheduled_time"
        case durationMinutes = "duration_minutes"
    }

    /// Initializer for creating new schedules
    init(
        id: UUID = UUID(),
        userId: UUID,
        taskId: UUID,
        timeframe: Timeframe,
        section: Section,
        scheduleDate: Date,
        sortOrder: Int = 0,
        createdDate: Date = Date(),
        parentScheduleId: UUID? = nil,
        scheduledTime: Date? = nil,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.taskId = taskId
        self.timeframe = timeframe
        self.section = section
        self.scheduleDate = scheduleDate
        self.sortOrder = sortOrder
        self.createdDate = createdDate
        self.parentScheduleId = parentScheduleId
        self.scheduledTime = scheduledTime
        self.durationMinutes = durationMinutes
    }

    /// Whether this schedule is a child (broken down from a parent)
    var isChildSchedule: Bool {
        parentScheduleId != nil
    }

    /// Whether this schedule can be broken down further (daily cannot)
    var canBreakdown: Bool {
        timeframe != .daily
    }

    /// The child timeframe for breakdown
    var childTimeframe: Timeframe? {
        timeframe.childTimeframe
    }
}
