//
//  TaskShare.swift
//  Focus IOS
//

import Foundation

struct TaskShare: Codable, Identifiable {
    let id: UUID
    let taskId: UUID
    let ownerId: UUID
    let sharedWithUserId: UUID?
    let shareToken: String?
    let createdDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case ownerId = "owner_id"
        case sharedWithUserId = "shared_with_user_id"
        case shareToken = "share_token"
        case createdDate = "created_date"
    }
}
