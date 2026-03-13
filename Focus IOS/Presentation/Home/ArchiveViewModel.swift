//
//  ArchiveViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

struct ArchiveSection: Identifiable {
    let id: String
    let title: String
    let tasks: [FocusTask]
}

@MainActor
class ArchiveViewModel: ObservableObject {
    @Published var sections: [ArchiveSection] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Edit mode
    @Published var isEditMode = false
    @Published var selectedIds: Set<UUID> = []
    @Published var showDeleteConfirmation = false
    @Published var showClearConfirmation = false

    var totalCount: Int {
        sections.reduce(0) { $0 + $1.tasks.count }
    }

    var allSelected: Bool {
        let allIds = Set(sections.flatMap { $0.tasks.map { $0.id } })
        return !allIds.isEmpty && allIds.isSubset(of: selectedIds)
    }

    func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = true
            selectedIds = []
        }
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedIds = []
        }
    }

    func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll() {
        selectedIds = Set(sections.flatMap { $0.tasks.map { $0.id } })
    }

    func deselectAll() {
        selectedIds = []
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty else { return }
        do {
            try await repository.deleteTasks(ids: selectedIds)
            selectedIds = []
            isEditMode = false
            await fetchCompletedItems()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAll() async {
        let allIds = Set(sections.flatMap { $0.tasks.map { $0.id } })
        guard !allIds.isEmpty else { return }
        do {
            try await repository.deleteTasks(ids: allIds)
            await fetchCompletedItems()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private let repository: TaskRepository
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository()) {
        self.repository = repository
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .taskCompletionChanged)
            .merge(with: NotificationCenter.default.publisher(for: .projectListChanged))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if notification.object as AnyObject? === self { return }
                if notification.object == nil,
                   LocalMutationTracker.isRecentlyMutated() { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchCompletedItems()
                }
            }
            .store(in: &cancellables)
    }

    func fetchCompletedItems() async {
        isLoading = true
        do {
            let completedItems = try await repository.fetchCompletedTopLevelTasks()
            sections = groupIntoSections(completedItems)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func groupIntoSections(_ items: [FocusTask]) -> [ArchiveSection] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let startOf7DaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let startOf14DaysAgo = calendar.date(byAdding: .day, value: -14, to: startOfToday)!

        var todayItems: [FocusTask] = []
        var dayBuckets: [Int: [FocusTask]] = [:]
        var lastWeekItems: [FocusTask] = []
        var weekRangeBuckets: [String: (title: String, sortDate: Date, items: [FocusTask])] = [:]

        for item in items {
            guard let completedDate = item.completedDate else { continue }
            let startOfCompletedDay = calendar.startOfDay(for: completedDate)

            if startOfCompletedDay >= startOfToday {
                todayItems.append(item)
            } else if startOfCompletedDay >= startOf7DaysAgo {
                let daysAgo = calendar.dateComponents([.day], from: startOfCompletedDay, to: startOfToday).day ?? 0
                dayBuckets[daysAgo, default: []].append(item)
            } else if startOfCompletedDay >= startOf14DaysAgo {
                lastWeekItems.append(item)
            } else {
                let range = weekRangeKeyAndTitle(for: completedDate, calendar: calendar)
                if weekRangeBuckets[range.key] != nil {
                    weekRangeBuckets[range.key]!.items.append(item)
                } else {
                    weekRangeBuckets[range.key] = (title: range.title, sortDate: startOfCompletedDay, items: [item])
                }
            }
        }

        var result: [ArchiveSection] = []

        if !todayItems.isEmpty {
            result.append(ArchiveSection(
                id: "today",
                title: "Today",
                tasks: sortByCompletedDate(todayItems)
            ))
        }

        for daysAgo in 1...6 {
            guard let items = dayBuckets[daysAgo], !items.isEmpty else { continue }
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!
            let title: String
            if daysAgo == 1 {
                title = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, MMM d"
                title = formatter.string(from: date)
            }
            result.append(ArchiveSection(
                id: "day-\(daysAgo)",
                title: title,
                tasks: sortByCompletedDate(items)
            ))
        }

        if !lastWeekItems.isEmpty {
            result.append(ArchiveSection(
                id: "lastWeek",
                title: "Last Week",
                tasks: sortByCompletedDate(lastWeekItems)
            ))
        }

        let sortedWeekRanges = weekRangeBuckets.values.sorted { $0.sortDate > $1.sortDate }
        for bucket in sortedWeekRanges {
            result.append(ArchiveSection(
                id: bucket.title,
                title: bucket.title,
                tasks: sortByCompletedDate(bucket.items)
            ))
        }

        return result
    }

    private func notifyTasksChanged() {
        LocalMutationTracker.markMutation()
        NotificationCenter.default.post(name: .projectListChanged, object: self)
    }

    private func sortByCompletedDate(_ items: [FocusTask]) -> [FocusTask] {
        items.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
    }

    private func weekRangeKeyAndTitle(for date: Date, calendar: Calendar) -> (key: String, title: String) {
        let day = calendar.component(.day, from: date)
        let weekStart = ((day - 1) / 7) * 7 + 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let weekEnd = min(weekStart + 6, daysInMonth)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)

        let key = "\(year)-\(month)-\(weekStart)"
        let title = "\(monthName) \(weekStart)-\(weekEnd)"
        return (key, title)
    }
}
