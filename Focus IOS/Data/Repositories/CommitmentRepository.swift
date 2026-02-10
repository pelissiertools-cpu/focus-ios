//
//  CommitmentRepository.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Supabase

/// Repository for managing task commitments in Supabase
class CommitmentRepository {
    private let supabase: SupabaseClient

    private struct CommitmentSortOrderUpdate: Encodable {
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case sortOrder = "sort_order"
        }
    }

    private struct CommitmentSectionSortUpdate: Encodable {
        let section: String
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case section
            case sortOrder = "sort_order"
        }
    }

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    /// Fetch commitments for a specific timeframe, date, and section
    func fetchCommitments(
        timeframe: Timeframe,
        date: Date,
        section: Section
    ) async throws -> [Commitment] {
        let (startDate, endDate) = Self.dateRange(for: timeframe, date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        let commitments: [Commitment] = try await supabase
            .from("commitments")
            .select()
            .eq("timeframe", value: timeframe.rawValue)
            .eq("section", value: section.rawValue)
            .gte("commitment_date", value: startStr)
            .lt("commitment_date", value: endStr)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return commitments
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

    /// Fetch all commitments for a specific task
    func fetchCommitments(forTask taskId: UUID) async throws -> [Commitment] {
        let commitments: [Commitment] = try await supabase
            .from("commitments")
            .select()
            .eq("task_id", value: taskId.uuidString)
            .execute()
            .value

        return commitments
    }

    /// Create a new commitment
    func createCommitment(_ commitment: Commitment) async throws -> Commitment {
        let createdCommitment: Commitment = try await supabase
            .from("commitments")
            .insert(commitment)
            .select()
            .single()
            .execute()
            .value

        return createdCommitment
    }

    /// Update an existing commitment
    func updateCommitment(_ commitment: Commitment) async throws {
        try await supabase
            .from("commitments")
            .update(commitment)
            .eq("id", value: commitment.id.uuidString)
            .execute()
    }

    /// Delete a commitment
    func deleteCommitment(id: UUID) async throws {
        try await supabase
            .from("commitments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Delete all commitments for a specific task
    func deleteCommitments(forTask taskId: UUID) async throws {
        try await supabase
            .from("commitments")
            .delete()
            .eq("task_id", value: taskId.uuidString)
            .execute()
    }

    // MARK: - Committed Task IDs

    private struct TaskIdRow: Decodable {
        let taskId: UUID
        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
        }
    }

    /// Fetch the set of task IDs that have at least one commitment (RLS scoped to current user)
    func fetchCommittedTaskIds() async throws -> Set<UUID> {
        let rows: [TaskIdRow] = try await supabase
            .from("commitments")
            .select("task_id")
            .execute()
            .value
        return Set(rows.map { $0.taskId })
    }

    // MARK: - Trickle-Down (Child Commitment) Methods

    /// Fetch child commitments for a parent commitment
    func fetchChildCommitments(parentId: UUID) async throws -> [Commitment] {
        let commitments: [Commitment] = try await supabase
            .from("commitments")
            .select()
            .eq("parent_commitment_id", value: parentId.uuidString)
            .order("commitment_date", ascending: true)
            .execute()
            .value

        return commitments
    }

    /// Create a child commitment (trickle-down from parent)
    func createChildCommitment(
        parentCommitment: Commitment,
        childDate: Date,
        targetTimeframe: Timeframe
    ) async throws -> Commitment {
        // Verify target timeframe is valid for breakdown
        guard parentCommitment.timeframe.availableBreakdownTimeframes.contains(targetTimeframe) else {
            throw CommitmentError.cannotBreakdown
        }

        let childCommitment = Commitment(
            userId: parentCommitment.userId,
            taskId: parentCommitment.taskId,
            timeframe: targetTimeframe,
            section: parentCommitment.section,
            commitmentDate: childDate,
            sortOrder: 0,
            parentCommitmentId: parentCommitment.id
        )

        let created: Commitment = try await supabase
            .from("commitments")
            .insert(childCommitment)
            .select()
            .single()
            .execute()
            .value

        return created
    }

    /// Update sort orders for multiple commitments
    func updateCommitmentSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async throws {
        for update in updates {
            let sortUpdate = CommitmentSortOrderUpdate(sortOrder: update.sortOrder)
            try await supabase
                .from("commitments")
                .update(sortUpdate)
                .eq("id", value: update.id.uuidString)
                .execute()
        }
    }

    /// Update sort orders and sections for multiple commitments
    func updateCommitmentSortOrdersAndSections(_ updates: [(id: UUID, sortOrder: Int, section: Section)]) async throws {
        for update in updates {
            let sortUpdate = CommitmentSectionSortUpdate(section: update.section.rawValue, sortOrder: update.sortOrder)
            try await supabase
                .from("commitments")
                .update(sortUpdate)
                .eq("id", value: update.id.uuidString)
                .execute()
        }
    }

}

/// Errors for commitment operations
enum CommitmentError: LocalizedError {
    case cannotBreakdown

    var errorDescription: String? {
        switch self {
        case .cannotBreakdown:
            return "This commitment cannot be broken down further."
        }
    }
}
