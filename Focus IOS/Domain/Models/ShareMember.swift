//
//  ShareMember.swift
//  Focus IOS
//

import Foundation

struct ShareMember: Codable, Identifiable {
    let userId: UUID
    let email: String
    let isOwner: Bool
    let joinedAt: Date?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case isOwner = "is_owner"
        case joinedAt = "joined_at"
    }
}
