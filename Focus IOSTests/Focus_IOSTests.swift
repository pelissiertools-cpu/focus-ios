//
//  Focus_IOSTests.swift
//  Focus IOSTests
//
//  Created by Gabriel  on 2026-02-04.
//

import Foundation
import Testing
@testable import Focus_IOS

@MainActor
struct Focus_IOSTests {

    // MARK: - FocusTask Tests

    @Test func focusTaskDefaultValues() {
        let userId = UUID()
        let task = FocusTask(userId: userId, title: "Test Task")
        #expect(task.title == "Test Task")
        #expect(task.userId == userId)
        #expect(task.isCompleted == false)
        #expect(task.priority == .low)
        #expect(task.type == .task)
        #expect(task.isSection == false)
        #expect(task.isCleared == false)
        #expect(task.isPinned == false)
        #expect(task.isInLibrary == true)
        #expect(task.sortOrder == 0)
        #expect(task.description == nil)
        #expect(task.parentTaskId == nil)
        #expect(task.categoryId == nil)
        #expect(task.projectId == nil)
        #expect(task.dueDate == nil)
        #expect(task.notificationEnabled == false)
        #expect(task.notificationDate == nil)
    }

    @Test func focusTaskCodableRoundtrip() throws {
        let categoryId = UUID()
        let original = FocusTask(
            userId: UUID(),
            title: "Test Task",
            description: "A description",
            type: .task,
            isCompleted: true,
            priority: .high,
            isSection: false,
            isCleared: true,
            isPinned: true,
            categoryId: categoryId
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FocusTask.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.userId == original.userId)
        #expect(decoded.title == original.title)
        #expect(decoded.description == original.description)
        #expect(decoded.type == original.type)
        #expect(decoded.isCompleted == original.isCompleted)
        #expect(decoded.priority == original.priority)
        #expect(decoded.isCleared == original.isCleared)
        #expect(decoded.isPinned == original.isPinned)
        #expect(decoded.categoryId == categoryId)
        #expect(decoded.parentTaskId == nil)
    }

    @Test func focusTaskCodingKeysMatchSnakeCase() throws {
        let task = FocusTask(userId: UUID(), title: "Test")
        let data = try JSONEncoder().encode(task)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Verify snake_case keys are used (matching Supabase column names)
        #expect(json["user_id"] != nil)
        #expect(json["is_completed"] != nil)
        #expect(json["created_date"] != nil)
        #expect(json["modified_date"] != nil)
        #expect(json["sort_order"] != nil)
        #expect(json["is_in_library"] != nil)
        #expect(json["is_section"] != nil)
        #expect(json["is_cleared"] != nil)
        #expect(json["is_pinned"] != nil)
        #expect(json["parent_task_id"] != nil)
    }

    // MARK: - Category Tests

    @Test func categoryCodableRoundtrip() throws {
        let original = Category(userId: UUID(), name: "Work", sortOrder: 3, type: .task)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Category.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.userId == original.userId)
        #expect(decoded.name == original.name)
        #expect(decoded.sortOrder == original.sortOrder)
        #expect(decoded.type == original.type)
        #expect(decoded.isSystem == false)
    }

    @Test func categoryDefaultValues() {
        let category = Category(userId: UUID(), name: "Personal")
        #expect(category.sortOrder == 0)
        #expect(category.type == .task)
        #expect(category.isSystem == false)
    }

    // MARK: - Priority Tests

    @Test func prioritySortOrder() {
        #expect(Priority.high.sortIndex < Priority.medium.sortIndex)
        #expect(Priority.medium.sortIndex < Priority.low.sortIndex)
    }

    @Test func priorityDisplayNames() {
        #expect(Priority.high.displayName == "High")
        #expect(Priority.medium.displayName == "Medium")
        #expect(Priority.low.displayName == "Low")
    }

    @Test func priorityCodable() throws {
        for priority in Priority.allCases {
            let data = try JSONEncoder().encode(priority)
            let decoded = try JSONDecoder().decode(Priority.self, from: data)
            #expect(decoded == priority)
        }
    }

    // MARK: - TaskType Tests

    @Test func taskTypeCodable() throws {
        for taskType in TaskType.allCases {
            let data = try JSONEncoder().encode(taskType)
            let decoded = try JSONDecoder().decode(TaskType.self, from: data)
            #expect(decoded == taskType)
        }
    }

    @Test func taskTypeDisplayNames() {
        #expect(TaskType.task.displayName == "Task")
        #expect(TaskType.project.displayName == "Project")
        #expect(TaskType.list.displayName == "List")
        #expect(TaskType.goal.displayName == "Goal")
    }
}
