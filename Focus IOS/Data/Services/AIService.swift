//
//  AIService.swift
//  Focus IOS
//

import Foundation
import Supabase

class AIService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    private struct GenerateSubtasksRequest: Encodable {
        let title: String
        let description: String?
    }

    private struct GenerateSubtasksResponse: Decodable {
        let subtasks: [String]?
        let error: String?
    }

    func generateSubtasks(title: String, description: String? = nil) async throws -> [String] {
        let request = GenerateSubtasksRequest(title: title, description: description)

        let response: GenerateSubtasksResponse = try await supabase.functions
            .invoke(
                "generate-subtasks",
                options: .init(body: request)
            )

        if let error = response.error {
            throw NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: error])
        }

        guard let subtasks = response.subtasks else {
            throw NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No subtasks returned"])
        }

        return subtasks
    }
}
