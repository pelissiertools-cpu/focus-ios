//
//  LogFilterable.swift
//  Focus IOS
//

import Foundation
import Combine

@MainActor
protocol LogFilterable: ObservableObject {
    // MARK: - Category filter
    var categories: [Category] { get }
    var selectedCategoryId: UUID? { get set }
    func selectCategory(_ categoryId: UUID?)
    func createCategory(name: String) async
    func deleteCategories(ids: Set<UUID>) async
    func mergeCategories(ids: Set<UUID>) async
    func renameCategory(id: UUID, newName: String) async
    func reorderCategories(fromOffsets: IndexSet, toOffset: Int) async

    // MARK: - Sort
    var sortOption: SortOption { get set }
    var sortDirection: SortDirection { get set }

    // MARK: - Schedule filter & due dates
    var scheduleFilter: ScheduleFilter? { get set }
    var scheduledTaskIds: Set<UUID> { get set }
    var taskDueDates: [UUID: Date] { get set }
    var scheduleRepository: ScheduleRepository { get }
    func toggleScheduleFilter(_ filter: ScheduleFilter)
    func fetchScheduledTaskIds() async

    // MARK: - Edit mode
    var isEditMode: Bool { get }
    var selectedItemIds: Set<UUID> { get }
    var selectedCount: Int { get }
    var allUncompletedSelected: Bool { get }
    func enterEditMode()
    func exitEditMode()
    func selectAllUncompleted()
    func deselectAll()

    // MARK: - Add item
    var showingAddItem: Bool { get set }

    // MARK: - Batch operations
    var showBatchDeleteConfirmation: Bool { get set }
    var showBatchMovePicker: Bool { get set }
    var showBatchScheduleSheet: Bool { get set }
    var selectedItems: [FocusTask] { get }
    func batchMoveToCategory(_ categoryId: UUID?) async
}

// Default implementations for trivial methods identical across all Log ViewModels.
extension LogFilterable {
    func selectCategory(_ categoryId: UUID?) {
        selectedCategoryId = categoryId
    }

    func toggleScheduleFilter(_ filter: ScheduleFilter) {
        if scheduleFilter == filter {
            scheduleFilter = nil
        } else {
            scheduleFilter = filter
        }
    }

    func fetchScheduledTaskIds() async {
        do {
            let summaries = try await scheduleRepository.fetchScheduleSummaries()
            scheduledTaskIds = Set(summaries.map { $0.taskId })

            // For each task, pick the smallest timeframe schedule → end of that period = due date
            var bestByTask: [UUID: (urgency: Int, endDate: Date)] = [:]
            for s in summaries {
                let endDate = ScheduleRepository.dateRange(for: s.timeframe, date: s.scheduleDate).end
                let urgency = s.timeframe.urgencyIndex
                if let existing = bestByTask[s.taskId] {
                    // Smaller timeframe wins; among same timeframe, earlier end date wins
                    if urgency < existing.urgency || (urgency == existing.urgency && endDate < existing.endDate) {
                        bestByTask[s.taskId] = (urgency, endDate)
                    }
                } else {
                    bestByTask[s.taskId] = (urgency, endDate)
                }
            }
            taskDueDates = bestByTask.mapValues { $0.endDate }
        } catch {
            // Silently handled — sorting falls back to creation date
        }
    }
}
