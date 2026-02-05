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

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    /// Fetch commitments for a specific timeframe, date, and section
    func fetchCommitments(
        timeframe: Timeframe,
        date: Date,
        section: Section
    ) async throws -> [Commitment] {
        let commitments: [Commitment] = try await supabase
            .from("commitments")
            .select()
            .eq("timeframe", value: timeframe.rawValue)
            .eq("section", value: section.rawValue)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return commitments
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
}
