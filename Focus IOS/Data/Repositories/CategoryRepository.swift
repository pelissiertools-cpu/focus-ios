//
//  CategoryRepository.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Supabase

/// Repository for managing categories in Supabase
class CategoryRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    /// Fetch all categories for the current user
    func fetchCategories() async throws -> [Category] {
        let categories: [Category] = try await supabase
            .from("categories")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value

        return categories
    }

    /// Fetch categories filtered by type (e.g. "task" or "project")
    func fetchCategories(type: String) async throws -> [Category] {
        let categories: [Category] = try await supabase
            .from("categories")
            .select()
            .eq("type", value: type)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return categories
    }

    /// Create a new category
    func createCategory(_ category: Category) async throws -> Category {
        let createdCategory: Category = try await supabase
            .from("categories")
            .insert(category)
            .select()
            .single()
            .execute()
            .value

        return createdCategory
    }

    /// Update an existing category
    func updateCategory(_ category: Category) async throws {
        try await supabase
            .from("categories")
            .update(category)
            .eq("id", value: category.id.uuidString)
            .execute()
    }

    /// Delete a category
    func deleteCategory(id: UUID) async throws {
        try await supabase
            .from("categories")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
