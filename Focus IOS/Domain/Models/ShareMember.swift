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
    let displayName: String?

    var id: UUID { userId }

    /// First name from displayName, or email prefix as fallback
    var firstName: String {
        if let name = displayName, !name.isEmpty {
            return name.components(separatedBy: " ").first ?? name
        }
        return email.components(separatedBy: "@").first ?? email
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case isOwner = "is_owner"
        case joinedAt = "joined_at"
        case displayName = "display_name"
    }
}
