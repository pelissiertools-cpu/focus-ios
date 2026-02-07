//
//  FocusTabViewModel.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import Foundation
import Combine
import Auth

@MainActor
class FocusTabViewModel: ObservableObject, TaskEditingViewModel {
    @Published var commitments: [Commitment] = []
    @Published var tasksMap: [UUID: FocusTask] = [:]  // taskId -> task
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]  // parentTaskId -> subtasks
    @Published var expandedTasks: Set<UUID> = []  // Track expanded tasks
    @Published var selectedTimeframe: Timeframe = .daily
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTaskForDetails: FocusTask?

    // Trickle-down state
    @Published var childCommitmentsMap: [UUID: [Commitment]] = [:]  // parentId -> children
    @Published var showBreakdownSheet = false
    @Published var selectedCommitmentForBreakdown: Commitment?

    private let commitmentRepository: CommitmentRepository
    private let taskRepository: TaskRepository
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(commitmentRepository: CommitmentRepository = CommitmentRepository(),
         taskRepository: TaskRepository = TaskRepository(),
         authService: AuthService) {
        self.commitmentRepository = commitmentRepository
        self.taskRepository = taskRepository
        self.authService = authService
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .taskCompletionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTaskCompletionNotification(notification)
            }
            .store(in: &cancellables)
    }

    private func handleTaskCompletionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo[TaskNotificationKeys.taskId] as? UUID,
              let isCompleted = userInfo[TaskNotificationKeys.isCompleted] as? Bool,
              let source = userInfo[TaskNotificationKeys.source] as? String,
              source == TaskNotificationSource.library.rawValue else {
            return
        }

        let completedDate = userInfo[TaskNotificationKeys.completedDate] as? Date

        // Update tasksMap if this task exists
        if var task = tasksMap[taskId] {
            task.isCompleted = isCompleted
            task.completedDate = completedDate
            tasksMap[taskId] = task
        }

        // Update subtasksMap if this task is a subtask
        for (parentId, var subtasks) in subtasksMap {
            if let index = subtasks.firstIndex(where: { $0.id == taskId }) {
                subtasks[index].isCompleted = isCompleted
                subtasks[index].completedDate = completedDate
                subtasksMap[parentId] = subtasks
                break
            }
        }
    }

    private func postTaskCompletionNotification(taskId: UUID, isCompleted: Bool, completedDate: Date?) {
        NotificationCenter.default.post(
            name: .taskCompletionChanged,
            object: nil,
            userInfo: [
                TaskNotificationKeys.taskId: taskId,
                TaskNotificationKeys.isCompleted: isCompleted,
                TaskNotificationKeys.completedDate: completedDate as Any,
                TaskNotificationKeys.source: TaskNotificationSource.focus.rawValue
            ]
        )
    }

    /// Fetch commitments for selected timeframe and date
    func fetchCommitments() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch both focus and extra sections
            let focusCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .focus
            )
            let extraCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .extra
            )

            self.commitments = focusCommitments + extraCommitments

            // Fetch associated tasks
            await fetchTasksForCommitments()

            // Fetch child commitments for trickle-down display
            await fetchChildCommitments()

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Fetch task details for all commitments
    private func fetchTasksForCommitments() async {
        let taskIds = Set(commitments.map { $0.taskId })

        do {
            // Fetch all tasks once instead of per-commitment
            let allTasks = try await taskRepository.fetchTasks()

            for taskId in taskIds {
                if let task = allTasks.first(where: { $0.id == taskId }) {
                    tasksMap[taskId] = task

                    // Fetch subtasks for parent tasks (tasks without parentTaskId)
                    if task.parentTaskId == nil {
                        let subtasks = try await taskRepository.fetchSubtasks(parentId: taskId)
                        if !subtasks.isEmpty {
                            subtasksMap[taskId] = subtasks
                        }
                    }
                }
            }
        } catch {
            print("Error fetching tasks: \(error)")
        }
    }

    /// Get subtasks for a task (sorted: uncompleted first)
    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        let subtasks = subtasksMap[taskId] ?? []
        return subtasks.sorted { !$0.isCompleted && $1.isCompleted }
    }

    /// Find a task by ID (searches both tasksMap and subtasksMap)
    func findTask(byId id: UUID) -> FocusTask? {
        if let task = tasksMap[id] {
            return task
        }
        for subtasks in subtasksMap.values {
            if let subtask = subtasks.first(where: { $0.id == id }) {
                return subtask
            }
        }
        return nil
    }

    /// Update a task's title
    func updateTask(_ task: FocusTask, newTitle: String) async {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Task title cannot be empty"
            return
        }

        do {
            var updatedTask = task
            updatedTask.title = newTitle
            updatedTask.modifiedDate = Date()

            try await taskRepository.updateTask(updatedTask)

            // Update local state - check both tasksMap and subtasksMap
            if tasksMap[task.id] != nil {
                tasksMap[task.id]?.title = newTitle
                tasksMap[task.id]?.modifiedDate = Date()
            }

            // Also check subtasks if this is a subtask
            if let parentId = task.parentTaskId,
               var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                subtasks[index].title = newTitle
                subtasks[index].modifiedDate = Date()
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a task (removes from Focus and deletes from database)
    func deleteTask(_ task: FocusTask) async {
        do {
            // Remove any commitments for this task
            let taskCommitments = commitments.filter { $0.taskId == task.id }
            for commitment in taskCommitments {
                try await commitmentRepository.deleteCommitment(id: commitment.id)
                commitments.removeAll { $0.id == commitment.id }
            }

            // Delete the task from database
            try await taskRepository.deleteTask(id: task.id)

            // Remove from local state
            tasksMap.removeValue(forKey: task.id)
            subtasksMap.removeValue(forKey: task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a subtask
    func deleteSubtask(_ subtask: FocusTask, parentId: UUID) async {
        do {
            try await taskRepository.deleteTask(id: subtask.id)

            // Update local state
            if var subtasks = subtasksMap[parentId] {
                subtasks.removeAll { $0.id == subtask.id }
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a new subtask
    func createSubtask(title: String, parentId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        do {
            let newSubtask = try await taskRepository.createSubtask(
                title: title,
                parentTaskId: parentId,
                userId: userId
            )

            // Update local state
            if var subtasks = subtasksMap[parentId] {
                subtasks.append(newSubtask)
                subtasksMap[parentId] = subtasks
            } else {
                subtasksMap[parentId] = [newSubtask]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Check if commitment date matches selected timeframe and date
    func isSameTimeframe(_ commitmentDate: Date, timeframe: Timeframe, selectedDate: Date) -> Bool {
        var calendar = Calendar.current

        switch timeframe {
        case .daily:
            return calendar.isDate(commitmentDate, inSameDayAs: selectedDate)
        case .weekly:
            calendar.firstWeekday = 1 // Sunday
            let commitmentWeek = calendar.component(.weekOfYear, from: commitmentDate)
            let selectedWeek = calendar.component(.weekOfYear, from: selectedDate)
            let commitmentYear = calendar.component(.yearForWeekOfYear, from: commitmentDate)
            let selectedYear = calendar.component(.yearForWeekOfYear, from: selectedDate)
            return commitmentWeek == selectedWeek && commitmentYear == selectedYear
        case .monthly:
            let commitmentMonth = calendar.component(.month, from: commitmentDate)
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let commitmentYear = calendar.component(.year, from: commitmentDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return commitmentMonth == selectedMonth && commitmentYear == selectedYear
        case .yearly:
            let commitmentYear = calendar.component(.year, from: commitmentDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return commitmentYear == selectedYear
        }
    }

    /// Check if can add more tasks to section
    func canAddTask(to section: Section, timeframe: Timeframe? = nil, date: Date? = nil) -> Bool {
        let checkTimeframe = timeframe ?? selectedTimeframe
        let checkDate = date ?? selectedDate

        let currentCount = commitments.filter {
            $0.section == section &&
            $0.timeframe == checkTimeframe &&
            isSameTimeframe($0.commitmentDate, timeframe: checkTimeframe, selectedDate: checkDate)
        }.count

        let maxTasks = section.maxTasks(for: checkTimeframe)
        return maxTasks == nil || currentCount < maxTasks!
    }

    /// Get current task count for section
    func taskCount(for section: Section, timeframe: Timeframe? = nil, date: Date? = nil) -> Int {
        let checkTimeframe = timeframe ?? selectedTimeframe
        let checkDate = date ?? selectedDate

        return commitments.filter {
            $0.section == section &&
            $0.timeframe == checkTimeframe &&
            isSameTimeframe($0.commitmentDate, timeframe: checkTimeframe, selectedDate: checkDate)
        }.count
    }

    /// Remove commitment
    func removeCommitment(_ commitment: Commitment) async {
        do {
            try await commitmentRepository.deleteCommitment(id: commitment.id)
            commitments.removeAll { $0.id == commitment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle task expansion
    func toggleExpanded(_ taskId: UUID) {
        if expandedTasks.contains(taskId) {
            expandedTasks.remove(taskId)
        } else {
            expandedTasks.insert(taskId)
        }
    }

    /// Check if task is expanded
    func isExpanded(_ taskId: UUID) -> Bool {
        expandedTasks.contains(taskId)
    }

    /// Toggle task completion
    func toggleTaskCompletion(_ task: FocusTask) async {
        let newIsCompleted = !task.isCompleted
        let newCompletedDate: Date? = newIsCompleted ? Date() : nil

        do {
            if task.isCompleted {
                try await taskRepository.uncompleteTask(id: task.id)
            } else {
                try await taskRepository.completeTask(id: task.id)
            }
            // Update local state
            if var updatedTask = tasksMap[task.id] {
                updatedTask.isCompleted = newIsCompleted
                updatedTask.completedDate = newCompletedDate
                tasksMap[task.id] = updatedTask
            }
            // Notify other views
            postTaskCompletionNotification(taskId: task.id, isCompleted: newIsCompleted, completedDate: newCompletedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle subtask completion
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        let newIsCompleted = !subtask.isCompleted
        let newCompletedDate: Date? = newIsCompleted ? Date() : nil

        do {
            if subtask.isCompleted {
                try await taskRepository.uncompleteTask(id: subtask.id)
            } else {
                try await taskRepository.completeTask(id: subtask.id)
            }
            // Update local state
            if var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                subtasks[index].isCompleted = newIsCompleted
                subtasks[index].completedDate = newCompletedDate
                subtasksMap[parentId] = subtasks
            }
            // Notify other views
            postTaskCompletionNotification(taskId: subtask.id, isCompleted: newIsCompleted, completedDate: newCompletedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trickle-Down (Breakdown) Methods

    /// Fetch child commitments for all current commitments that can be broken down
    func fetchChildCommitments() async {
        for commitment in commitments where commitment.canBreakdown {
            do {
                let children = try await commitmentRepository.fetchChildCommitments(
                    parentId: commitment.id
                )
                childCommitmentsMap[commitment.id] = children
            } catch {
                print("Error fetching children for \(commitment.id): \(error)")
            }
        }
    }

    /// Get child commitments for a parent
    func getChildCommitments(for parentId: UUID) -> [Commitment] {
        childCommitmentsMap[parentId] ?? []
    }

    /// Get child count for a commitment
    func childCount(for commitmentId: UUID) -> Int {
        childCommitmentsMap[commitmentId]?.count ?? 0
    }

    /// Break down a commitment to a specific date and timeframe
    func breakdownCommitment(_ commitment: Commitment, toDate date: Date, targetTimeframe: Timeframe) async {
        do {
            let child = try await commitmentRepository.createChildCommitment(
                parentCommitment: commitment,
                childDate: date,
                targetTimeframe: targetTimeframe
            )

            // Update local state
            if var children = childCommitmentsMap[commitment.id] {
                children.append(child)
                childCommitmentsMap[commitment.id] = children
            } else {
                childCommitmentsMap[commitment.id] = [child]
            }

            // Add to commitments list so it appears when viewing child timeframe
            commitments.append(child)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Calculate available slots for any target timeframe breakdown
    func availableSlotsForBreakdown(_ commitment: Commitment, targetTimeframe: Timeframe) -> [Date] {
        guard commitment.timeframe.availableBreakdownTimeframes.contains(targetTimeframe) else {
            return []
        }

        let calendar = Calendar.current
        var slots: [Date] = []

        // Generate slots based on target timeframe within the commitment's date range
        switch targetTimeframe {
        case .monthly:
            // Generate all 12 months of the commitment's year
            let year = calendar.component(.year, from: commitment.commitmentDate)
            for month in 1...12 {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = 1
                if let date = calendar.date(from: components) {
                    slots.append(date)
                }
            }

        case .weekly:
            // Generate weeks based on parent timeframe scope
            switch commitment.timeframe {
            case .yearly:
                // All weeks in the year
                let year = calendar.component(.year, from: commitment.commitmentDate)
                var components = DateComponents()
                components.year = year
                components.month = 1
                components.day = 1
                guard let yearStart = calendar.date(from: components) else { return [] }

                var currentDate = yearStart
                var seenWeeks: Set<Int> = []
                while calendar.component(.year, from: currentDate) == year {
                    let weekOfYear = calendar.component(.weekOfYear, from: currentDate)
                    if !seenWeeks.contains(weekOfYear) {
                        seenWeeks.insert(weekOfYear)
                        if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate)) {
                            slots.append(weekStart)
                        }
                    }
                    guard let nextDate = calendar.date(byAdding: .day, value: 7, to: currentDate) else { break }
                    currentDate = nextDate
                }

            case .monthly:
                // All weeks in the month
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: commitment.commitmentDate)),
                      let monthRange = calendar.range(of: .day, in: .month, for: commitment.commitmentDate) else {
                    return []
                }

                var seenWeeks: Set<Int> = []
                for day in monthRange {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        let weekOfYear = calendar.component(.weekOfYear, from: date)
                        if !seenWeeks.contains(weekOfYear) {
                            seenWeeks.insert(weekOfYear)
                            if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) {
                                slots.append(weekStart)
                            }
                        }
                    }
                }

            default:
                break
            }

        case .daily:
            // Generate days based on parent timeframe scope
            switch commitment.timeframe {
            case .yearly:
                // All days in the year (too many - use calendar picker navigation instead)
                // Return empty and let the calendar picker handle display
                return []

            case .monthly:
                // All days in the month
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: commitment.commitmentDate)),
                      let monthRange = calendar.range(of: .day, in: .month, for: commitment.commitmentDate) else {
                    return []
                }

                for day in monthRange {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        slots.append(date)
                    }
                }

            case .weekly:
                // All 7 days of the week
                guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: commitment.commitmentDate)) else {
                    return []
                }
                for dayOffset in 0..<7 {
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) {
                        slots.append(date)
                    }
                }

            default:
                break
            }

        case .yearly:
            // Cannot break down to yearly
            return []
        }

        // Filter out already-used slots for this target timeframe
        let existingChildren = getChildCommitments(for: commitment.id)
            .filter { $0.timeframe == targetTimeframe }
        let existingDates = Set(existingChildren.map { calendar.startOfDay(for: $0.commitmentDate) })

        return slots.filter { !existingDates.contains(calendar.startOfDay(for: $0)) }
    }
}
