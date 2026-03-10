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
    var taskScheduleDates: [UUID: Date] { get set }
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
        // Pre-populate from cache for instant display
        let cache = AppDataCache.shared
        if scheduledTaskIds.isEmpty && cache.hasLoadedScheduleSummaries {
            scheduledTaskIds = cache.scheduledTaskIds
            taskDueDates = Self.buildDueDates(from: cache.scheduleSummaries)
            taskScheduleDates = Self.buildScheduleDates(from: cache.scheduleSummaries)
        }

        do {
            let summaries = try await scheduleRepository.fetchScheduleSummaries()
            scheduledTaskIds = Set(summaries.map { $0.taskId })
            taskDueDates = Self.buildDueDates(from: summaries)
            taskScheduleDates = Self.buildScheduleDates(from: summaries)

            // Update cache
            cache.scheduleSummaries = summaries
            cache.scheduledTaskIds = scheduledTaskIds
            cache.hasLoadedScheduleSummaries = true
        } catch {
            // Silently handled — sorting falls back to creation date
        }
    }

    private static func buildDueDates(from summaries: [ScheduleRepository.ScheduleSummary]) -> [UUID: Date] {
        var bestByTask: [UUID: (urgency: Int, endDate: Date)] = [:]
        for s in summaries {
            let endDate = ScheduleRepository.dateRange(for: s.timeframe, date: s.scheduleDate).end
            let urgency = s.timeframe.urgencyIndex
            if let existing = bestByTask[s.taskId] {
                if urgency < existing.urgency || (urgency == existing.urgency && endDate < existing.endDate) {
                    bestByTask[s.taskId] = (urgency, endDate)
                }
            } else {
                bestByTask[s.taskId] = (urgency, endDate)
            }
        }
        return bestByTask.mapValues { $0.endDate }
    }

    /// Earliest schedule date per task (for inline display)
    private static func buildScheduleDates(from summaries: [ScheduleRepository.ScheduleSummary]) -> [UUID: Date] {
        var earliest: [UUID: Date] = [:]
        for s in summaries {
            let date = Calendar.current.startOfDay(for: s.scheduleDate)
            if let existing = earliest[s.taskId] {
                if date < existing { earliest[s.taskId] = date }
            } else {
                earliest[s.taskId] = date
            }
        }
        return earliest
    }
}
