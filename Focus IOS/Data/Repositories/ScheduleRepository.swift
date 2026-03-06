//
//  ScheduleRepository.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Supabase

/// Repository for managing task schedules in Supabase
class ScheduleRepository {
    private let supabase: SupabaseClient

    private struct ScheduleSortOrderUpdate: Encodable {
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case sortOrder = "sort_order"
        }
    }

    private struct ScheduleSectionSortUpdate: Encodable {
        let section: String
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case section
            case sortOrder = "sort_order"
        }
    }

    private struct ScheduleDateSortUpdate: Encodable {
        let scheduleDate: Date
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case scheduleDate = "schedule_date"
            case sortOrder = "sort_order"
        }
    }

    private struct ScheduleTimeUpdate: Encodable {
        let scheduledTime: Date?
        let durationMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case scheduledTime = "scheduled_time"
            case durationMinutes = "duration_minutes"
        }

        // Explicitly encode nil as null so Supabase sets columns to NULL
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scheduledTime, forKey: .scheduledTime)
            try container.encode(durationMinutes, forKey: .durationMinutes)
        }
    }

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    /// Fetch overdue daily schedules (schedule_date before today, task not yet completed)
    func fetchOverdueSchedules() async throws -> [Schedule] {
        let today = Calendar.current.startOfDay(for: Date())

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let todayStr = formatter.string(from: today)

        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .eq("timeframe", value: Timeframe.daily.rawValue)
            .lt("schedule_date", value: todayStr)
            .order("schedule_date", ascending: false)
            .execute()
            .value

        return schedules
    }

    /// Fetch schedules for a specific timeframe, date, and section
    func fetchSchedules(
        timeframe: Timeframe,
        date: Date,
        section: Section
    ) async throws -> [Schedule] {
        let (startDate, endDate) = Self.dateRange(for: timeframe, date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .eq("timeframe", value: timeframe.rawValue)
            .eq("section", value: section.rawValue)
            .gte("schedule_date", value: startStr)
            .lt("schedule_date", value: endStr)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return schedules
    }

    /// Compute the start (inclusive) and end (exclusive) dates for a timeframe period
    static func dateRange(for timeframe: Timeframe, date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday

        switch timeframe {
        case .daily:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let start = calendar.date(from: components)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: components)!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .yearly:
            let components = calendar.dateComponents([.year], from: date)
            let start = calendar.date(from: components)!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    /// Fetch all descendant-timeframe schedules within a parent timeframe's date range (rollup view).
    /// e.g. weekly parent → daily items for that week
    ///      monthly parent → weekly + daily items for that month (grouped by week in the ViewModel)
    ///      yearly parent  → monthly + weekly + daily items for that year
    func fetchRollupSchedules(parentTimeframe: Timeframe, date: Date) async throws -> [Schedule] {
        let descendantTimeframes = parentTimeframe.availableBreakdownTimeframes
        guard !descendantTimeframes.isEmpty else { return [] }

        let (startDate, endDate) = Self.dateRange(for: parentTimeframe, date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .in("timeframe", values: descendantTimeframes.map { $0.rawValue })
            .gte("schedule_date", value: startStr)
            .lt("schedule_date", value: endStr)
            .order("schedule_date", ascending: true)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return schedules
    }

    /// Fetch all schedules for a specific task
    func fetchSchedules(forTask taskId: UUID) async throws -> [Schedule] {
        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .eq("task_id", value: taskId.uuidString)
            .execute()
            .value

        return schedules
    }

    /// Create a new schedule
    func createSchedule(_ schedule: Schedule) async throws -> Schedule {
        let createdSchedule: Schedule = try await supabase
            .from("schedules")
            .insert(schedule)
            .select()
            .single()
            .execute()
            .value

        return createdSchedule
    }

    /// Update an existing schedule
    func updateSchedule(_ schedule: Schedule) async throws {
        try await supabase
            .from("schedules")
            .update(schedule)
            .eq("id", value: schedule.id.uuidString)
            .execute()
    }

    /// Delete a schedule
    func deleteSchedule(id: UUID) async throws {
        try await supabase
            .from("schedules")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Delete all schedules for a specific task
    func deleteSchedules(forTask taskId: UUID) async throws {
        try await supabase
            .from("schedules")
            .delete()
            .eq("task_id", value: taskId.uuidString)
            .execute()
    }

    /// Delete all schedules for multiple tasks in a single query
    func deleteSchedules(forTasks taskIds: Set<UUID>) async throws {
        guard !taskIds.isEmpty else { return }
        try await supabase
            .from("schedules")
            .delete()
            .in("task_id", values: taskIds.map { $0.uuidString })
            .execute()
    }

    // MARK: - Scheduled Task IDs & Due Dates

    struct ScheduleSummary: Decodable {
        let id: UUID
        let taskId: UUID
        let timeframe: Timeframe
        let scheduleDate: Date
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case id
            case taskId = "task_id"
            case timeframe
            case scheduleDate = "schedule_date"
            case sortOrder = "sort_order"
        }
    }

    /// Fetch lightweight summaries of all schedules
    func fetchScheduleSummaries() async throws -> [ScheduleSummary] {
        let rows: [ScheduleSummary] = try await supabase
            .from("schedules")
            .select("id, task_id, timeframe, schedule_date, sort_order")
            .execute()
            .value
        return rows
    }

    // MARK: - Trickle-Down (Child Schedule) Methods

    /// Fetch child schedules for a parent schedule
    func fetchChildSchedules(parentId: UUID) async throws -> [Schedule] {
        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .eq("parent_schedule_id", value: parentId.uuidString)
            .order("schedule_date", ascending: true)
            .execute()
            .value

        return schedules
    }

    /// Create a child schedule (trickle-down from parent)
    func createChildSchedule(
        parentSchedule: Schedule,
        childDate: Date,
        targetTimeframe: Timeframe
    ) async throws -> Schedule {
        // Verify target timeframe is valid for breakdown
        guard parentSchedule.timeframe.availableBreakdownTimeframes.contains(targetTimeframe) else {
            throw ScheduleError.cannotBreakdown
        }

        let childSchedule = Schedule(
            userId: parentSchedule.userId,
            taskId: parentSchedule.taskId,
            timeframe: targetTimeframe,
            section: parentSchedule.section,
            scheduleDate: childDate,
            sortOrder: 0,
            parentScheduleId: parentSchedule.id
        )

        let created: Schedule = try await supabase
            .from("schedules")
            .insert(childSchedule)
            .select()
            .single()
            .execute()
            .value

        return created
    }

    /// Update sort orders for multiple schedules
    func updateScheduleSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async throws {
        for update in updates {
            let sortUpdate = ScheduleSortOrderUpdate(sortOrder: update.sortOrder)
            try await supabase
                .from("schedules")
                .update(sortUpdate)
                .eq("id", value: update.id.uuidString)
                .execute()
        }
    }

    /// Update sort orders and sections for multiple schedules
    func updateScheduleSortOrdersAndSections(_ updates: [(id: UUID, sortOrder: Int, section: Section)]) async throws {
        for update in updates {
            let sortUpdate = ScheduleSectionSortUpdate(section: update.section.rawValue, sortOrder: update.sortOrder)
            try await supabase
                .from("schedules")
                .update(sortUpdate)
                .eq("id", value: update.id.uuidString)
                .execute()
        }
    }

    /// Update schedule date and sort order (for cross-section drag)
    func updateScheduleDateAndSortOrder(id: UUID, date: Date, sortOrder: Int) async throws {
        let update = ScheduleDateSortUpdate(scheduleDate: date, sortOrder: sortOrder)
        try await supabase
            .from("schedules")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Scheduled Time Methods

    /// Update only the scheduled time and duration for a schedule
    func updateScheduleTime(id: UUID, scheduledTime: Date?, durationMinutes: Int?) async throws {
        let update = ScheduleTimeUpdate(scheduledTime: scheduledTime, durationMinutes: durationMinutes)
        try await supabase
            .from("schedules")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Fetch schedules that have a scheduled time for a given day
    func fetchTimedSchedules(for date: Date) async throws -> [Schedule] {
        let (startDate, endDate) = Self.dateRange(for: .daily, date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .not("scheduled_time", operator: .is, value: "null")
            .gte("schedule_date", value: formatter.string(from: startDate))
            .lt("schedule_date", value: formatter.string(from: endDate))
            .order("scheduled_time", ascending: true)
            .execute()
            .value

        return schedules
    }

}

/// Errors for schedule operations
enum ScheduleError: LocalizedError {
    case cannotBreakdown

    var errorDescription: String? {
        switch self {
        case .cannotBreakdown:
            return "This schedule cannot be broken down further."
        }
    }
}
