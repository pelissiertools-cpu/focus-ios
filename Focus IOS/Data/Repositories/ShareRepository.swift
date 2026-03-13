//
//  ShareRepository.swift
//  Focus IOS
//

import Foundation
import Supabase

class ShareRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    // MARK: - Create Share

    private struct NewShare: Encodable {
        let taskId: UUID
        let ownerId: UUID
        let shareToken: String

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case ownerId = "owner_id"
            case shareToken = "share_token"
        }
    }

    /// Create a share link for a task/project/list. Returns the share token.
    func createShare(taskId: UUID, ownerId: UUID) async throws -> String {
        // Check if a share link already exists for this task
        let existing: [TaskShare] = try await supabase
            .from("task_shares")
            .select()
            .eq("task_id", value: taskId.uuidString)
            .eq("owner_id", value: ownerId.uuidString)
            .not("share_token", operator: .is, value: "null")
            .limit(1)
            .execute()
            .value

        if let existingToken = existing.first?.shareToken {
            return existingToken
        }

        let token = UUID().uuidString
        let newShare = NewShare(taskId: taskId, ownerId: ownerId, shareToken: token)

        try await supabase
            .from("task_shares")
            .insert(newShare)
            .execute()

        return token
    }

    // MARK: - Accept Share

    /// Accept a share via token. Calls the accept_share RPC. Returns the shared task ID.
    func acceptShare(token: String) async throws -> UUID {
        let response: AnyJSON = try await supabase
            .rpc("accept_share", params: ["p_token": token])
            .execute()
            .value

        guard let uuidString = response.value as? String,
              let taskId = UUID(uuidString: uuidString) else {
            throw ShareError.invalidResponse
        }

        return taskId
    }

    // MARK: - Fetch Shared Task IDs

    private struct ShareRow: Decodable {
        let taskId: UUID
        enum CodingKeys: String, CodingKey { case taskId = "task_id" }
    }

    /// Fetch all task IDs that are shared (either by me or with me), where at least one recipient has accepted.
    func fetchSharedTaskIds() async throws -> Set<UUID> {
        let rows: [ShareRow] = try await supabase
            .from("task_shares")
            .select("task_id")
            .not("shared_with_user_id", operator: .is, value: "null")
            .execute()
            .value

        return Set(rows.map { $0.taskId })
    }

    // MARK: - Fetch Members

    /// Fetch all members of a shared task via the get_share_members RPC.
    func fetchMembers(taskId: UUID) async throws -> [ShareMember] {
        let members: [ShareMember] = try await supabase
            .rpc("get_share_members", params: ["p_task_id": taskId.uuidString])
            .execute()
            .value

        return members
    }

    /// Remove a specific member from a shared task (owner action).
    func removeMember(taskId: UUID, userId: UUID) async throws {
        try await supabase
            .from("task_shares")
            .delete()
            .eq("task_id", value: taskId.uuidString)
            .eq("shared_with_user_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Remove Share (owner)

    /// Remove all shares for a task (owner unsharing).
    func removeShare(taskId: UUID) async throws {
        try await supabase
            .from("task_shares")
            .delete()
            .eq("task_id", value: taskId.uuidString)
            .execute()
    }

    // MARK: - Leave Share (recipient)

    /// Leave a share (recipient removing themselves).
    func leaveShare(taskId: UUID, userId: UUID) async throws {
        try await supabase
            .from("task_shares")
            .delete()
            .eq("task_id", value: taskId.uuidString)
            .eq("shared_with_user_id", value: userId.uuidString)
            .execute()
    }
}

enum ShareError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from share service"
        }
    }
}
