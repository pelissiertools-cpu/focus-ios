//
//  FocusTabViewModel.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI
import Combine
import Auth

// MARK: - Focus Section Config

struct FocusSectionConfig {
    let taskFont: Font
    let verticalPadding: CGFloat
    let containerMinHeight: CGFloat
    let completedTaskFont: Font
    let completedVerticalPadding: CGFloat
    let completedOpacity: Double
}

// MARK: - Flat Display Item for Focus List

enum FocusFlatDisplayItem: Identifiable {
    case sectionHeader(Section)
    case commitment(Commitment)           // uncompleted — movable
    case completedCommitment(Commitment)   // completed — not movable
    case subtask(FocusTask, parentCommitment: Commitment)
    case addSubtaskRow(parentId: UUID, parentCommitment: Commitment)
    case emptyState(Section)
    case allDoneState
    case donePill
    case focusSpacer(CGFloat)

    var id: String {
        switch self {
        case .sectionHeader(let section):
            return "header-\(section.rawValue)"
        case .commitment(let c):
            return c.id.uuidString
        case .completedCommitment(let c):
            return c.id.uuidString  // Same ID as .commitment for smooth in-place transition
        case .subtask(let task, _):
            return "subtask-\(task.id.uuidString)"
        case .addSubtaskRow(let parentId, _):
            return "add-subtask-\(parentId.uuidString)"
        case .emptyState(let section):
            return "empty-\(section.rawValue)"
        case .allDoneState:
            return "all-done"
        case .donePill:
            return "done-pill"
        case .focusSpacer:
            return "focus-spacer"
        }
    }
}

@MainActor
class FocusTabViewModel: ObservableObject, TaskEditingViewModel {
    @Published var commitments: [Commitment] = []
    @Published var tasksMap: [UUID: FocusTask] = [:]  // taskId -> task
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]  // parentTaskId -> subtasks
    @Published var expandedTasks: Set<UUID> = []  // Track expanded tasks
    @Published var selectedTimeframe: Timeframe = .daily
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var hasLoadedInitialData = false
    @Published var errorMessage: String?
    @Published var selectedTaskForDetails: FocusTask?

    // Trickle-down state
    @Published var childCommitmentsMap: [UUID: [Commitment]] = [:]  // parentId -> children
    @Published var showCommitSheet = false
    @Published var selectedCommitmentForCommit: Commitment?

    // Reschedule state (triggered from context menu)
    @Published var selectedCommitmentForReschedule: Commitment?
    @Published var showRescheduleSheet = false

    // Subtask commit state (for committing subtasks that don't have their own commitment)
    @Published var selectedSubtaskForCommit: FocusTask?
    @Published var selectedParentCommitmentForSubtaskCommit: Commitment?
    @Published var showSubtaskCommitSheet = false

    // Section collapse and add task state
    @Published var isExtraSectionCollapsed: Bool = true
    @Published var isDoneSubsectionCollapsed: Bool = true  // Closed by default
    @Published var isFocusDoneExpanded: Bool = false  // Focus "All Done" completed list hidden by default
    @Published var isFocusDoneCollapsing: Bool = false  // True during staggered collapse animation
    @Published var focusDoneHiddenIds: Set<UUID> = []  // IDs being animated out during collapse
    @Published var allDoneCheckPulse: Bool = false  // Checkmark scale pulse after collapse
    @Published var showAddTaskSheet: Bool = false
    @Published var addTaskSection: Section = .extra

    // Timeline ViewModel (owns all calendar timeline state and methods)
    @Published var timelineVM: TimelineViewModel!

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
        self.timelineVM = TimelineViewModel(
            parent: self,
            commitmentRepository: commitmentRepository,
            taskRepository: taskRepository,
            authService: authService
        )
        // Forward timelineVM changes so FocusTabView re-renders on drag state updates
        timelineVM.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
              source == TaskNotificationSource.log.rawValue else {
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
        var foundParentId: UUID? = nil
        for (parentId, var subtasks) in subtasksMap {
            if let index = subtasks.firstIndex(where: { $0.id == taskId }) {
                subtasks[index].isCompleted = isCompleted
                subtasks[index].completedDate = completedDate
                subtasksMap[parentId] = subtasks
                foundParentId = parentId
                break
            }
        }

        // If a subtask was updated, check auto-complete for its parent
        if let parentId = foundParentId, let subtasks = subtasksMap[parentId] {
            // Reconstruct pre-toggle states (invert the toggled subtask)
            let preToggleStates = subtasks.map { sub in
                sub.id == taskId ? !isCompleted : sub.isCompleted
            }
            let shouldAutoComplete = checkShouldAutoCompleteParent(parentId: parentId, subtasks: subtasks)

            _Concurrency.Task { @MainActor in
                do {
                    if shouldAutoComplete {
                        if var parentTask = self.tasksMap[parentId], !parentTask.isCompleted {
                            parentTask.previousCompletionState = preToggleStates
                            try await self.taskRepository.updateTask(parentTask)
                            try await self.taskRepository.completeTask(id: parentId)
                            parentTask.isCompleted = true
                            parentTask.completedDate = Date()
                            self.tasksMap[parentId] = parentTask
                            self.postTaskCompletionNotification(
                                taskId: parentId,
                                isCompleted: true,
                                completedDate: parentTask.completedDate
                            )
                        }
                    } else {
                        if var parentTask = self.tasksMap[parentId], parentTask.isCompleted {
                            try await self.taskRepository.uncompleteTask(id: parentId)
                            parentTask.isCompleted = false
                            parentTask.completedDate = nil
                            self.tasksMap[parentId] = parentTask
                            self.postTaskCompletionNotification(
                                taskId: parentId,
                                isCompleted: false,
                                completedDate: nil
                            )
                        }
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }

        // Refresh subtasks from DB if parent's subtasks were changed
        if let subtasksChanged = userInfo[TaskNotificationKeys.subtasksChanged] as? Bool,
           subtasksChanged {
            _Concurrency.Task { @MainActor in
                if let refreshed = try? await self.taskRepository.fetchSubtasks(parentId: taskId),
                   !refreshed.isEmpty {
                    self.subtasksMap[taskId] = refreshed
                }
            }
        }
    }

    private func postTaskCompletionNotification(taskId: UUID, isCompleted: Bool, completedDate: Date?, subtasksChanged: Bool = false) {
        NotificationCenter.default.post(
            name: .taskCompletionChanged,
            object: nil,
            userInfo: [
                TaskNotificationKeys.taskId: taskId,
                TaskNotificationKeys.isCompleted: isCompleted,
                TaskNotificationKeys.completedDate: completedDate as Any,
                TaskNotificationKeys.source: TaskNotificationSource.focus.rawValue,
                TaskNotificationKeys.subtasksChanged: subtasksChanged
            ]
        )
    }

    /// Fetch commitments for selected timeframe and date
    func fetchCommitments() async {
        // Only show loading spinner on initial load (no cached data yet)
        let isInitialLoad = !hasLoadedInitialData
        if isInitialLoad {
            isLoading = true
        }
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

            // Fetch timed commitments for calendar timeline
            await timelineVM.fetchTimedCommitments()

            hasLoadedInitialData = true
            isLoading = false
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    /// Fetch task details for all commitments
    private func fetchTasksForCommitments() async {
        let taskIds = Array(Set(commitments.map { $0.taskId }))
        guard !taskIds.isEmpty else { return }

        do {
            // Fetch only the tasks referenced by commitments
            let tasks = try await taskRepository.fetchTasksByIds(taskIds)

            for task in tasks {
                tasksMap[task.id] = task

                // Fetch subtasks for any task that has a commitment in this view
                let subtasks = try await taskRepository.fetchSubtasks(parentId: task.id)
                if !subtasks.isEmpty {
                    subtasksMap[task.id] = subtasks
                }
            }
        } catch {
            print("Error fetching tasks: \(error)")
        }
    }

    /// Refresh subtasks for a parent task from the database
    func refreshSubtasks(for parentId: UUID) async {
        do {
            let subtasks = try await taskRepository.fetchSubtasks(parentId: parentId)
            subtasksMap[parentId] = subtasks
            for subtask in subtasks {
                tasksMap[subtask.id] = subtask
            }
        } catch {
            // Silently fail — subtasks will refresh on next full load
        }
    }

    /// Get subtasks for a task (sorted: uncompleted first)
    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        let subtasks = subtasksMap[taskId] ?? []
        return subtasks.sorted { !$0.isCompleted && $1.isCompleted }
    }

    /// Get uncompleted subtasks sorted by sortOrder
    func getUncompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Get completed subtasks
    func getCompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { $0.isCompleted }
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

    /// Delete a task - only hard-deletes if task originated in Focus (not Log)
    func deleteTask(_ task: FocusTask) async {
        // For Log-origin tasks, use removeCommitment() instead
        // This method should only hard-delete Focus-origin tasks
        guard !task.isInLog else {
            return
        }

        do {
            // Remove all commitments for this task (with cascade)
            let taskCommitments = commitments.filter { $0.taskId == task.id }
            for commitment in taskCommitments {
                try await deleteCommitmentWithDescendants(commitment)
            }

            // Hard-delete the task (Focus-origin only)
            try await taskRepository.deleteTask(id: task.id)

            // Remove from local state
            tasksMap.removeValue(forKey: task.id)
            subtasksMap.removeValue(forKey: task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently delete a task regardless of origin (Log or Focus).
    /// Removes ALL commitments for this task and its subtasks, then hard-deletes everything.
    func permanentlyDeleteTask(_ task: FocusTask) async {
        do {
            // Delete subtask commitments and subtasks
            let subtasks = subtasksMap[task.id] ?? []
            for subtask in subtasks {
                try await commitmentRepository.deleteCommitments(forTask: subtask.id)
                try await taskRepository.deleteTask(id: subtask.id)
            }

            // Delete ALL commitments for this task (covers all timeframes)
            try await commitmentRepository.deleteCommitments(forTask: task.id)

            // Delete the task itself
            try await taskRepository.deleteTask(id: task.id)

            // Clean up local state
            tasksMap.removeValue(forKey: task.id)
            subtasksMap.removeValue(forKey: task.id)
            for subtask in subtasks {
                tasksMap.removeValue(forKey: subtask.id)
            }
            let deletedTaskIds = Set([task.id] + subtasks.map { $0.id })
            commitments.removeAll { deletedTaskIds.contains($0.taskId) }
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

    /// Create a new subtask (protocol conformance)
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

    /// Create a plain subtask (no child commitment — just a task-level child)
    func createPlainSubtask(title: String, parentId: UUID) async {
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

            if var subtasks = subtasksMap[parentId] {
                subtasks.append(newSubtask)
                subtasksMap[parentId] = subtasks
            } else {
                subtasksMap[parentId] = [newSubtask]
            }

            tasksMap[newSubtask.id] = newSubtask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Batch-create plain subtasks, updating the view once at the end
    func createPlainSubtasks(titles: [String], parentId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        var created: [FocusTask] = []
        for title in titles {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            do {
                let newSubtask = try await taskRepository.createSubtask(
                    title: title,
                    parentTaskId: parentId,
                    userId: userId
                )
                created.append(newSubtask)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Single batch update — one view re-render
        if !created.isEmpty {
            var existing = subtasksMap[parentId] ?? []
            existing.append(contentsOf: created)
            subtasksMap[parentId] = existing
            for subtask in created {
                tasksMap[subtask.id] = subtask
            }
        }
    }

    /// Create a new subtask with a commitment at the parent's timeframe (breakdown use case)
    func createSubtask(title: String, parentId: UUID, parentCommitment: Commitment) async {
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

            // Create a commitment for this subtask at the parent's timeframe
            let subtaskCommitment = Commitment(
                userId: userId,
                taskId: newSubtask.id,
                timeframe: parentCommitment.timeframe,
                section: parentCommitment.section,
                commitmentDate: parentCommitment.commitmentDate,
                sortOrder: 0,
                parentCommitmentId: parentCommitment.id
            )
            let created = try await commitmentRepository.createCommitment(subtaskCommitment)
            commitments.append(created)

            // Track as child of parent commitment
            if var children = childCommitmentsMap[parentCommitment.id] {
                children.append(created)
                childCommitmentsMap[parentCommitment.id] = children
            } else {
                childCommitmentsMap[parentCommitment.id] = [created]
            }

            // Add subtask to tasksMap so it can be displayed independently
            tasksMap[newSubtask.id] = newSubtask
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

    /// Recursively delete a commitment and all its descendants (cascade down)
    func deleteCommitmentWithDescendants(_ commitment: Commitment) async throws {
        // First, recursively delete all children
        let children = childCommitmentsMap[commitment.id] ?? []
        for child in children {
            try await deleteCommitmentWithDescendants(child)
        }

        // Clean up local state for this commitment's children
        childCommitmentsMap.removeValue(forKey: commitment.id)

        // Delete this commitment from database
        try await commitmentRepository.deleteCommitment(id: commitment.id)

        // Remove from local state
        commitments.removeAll { $0.id == commitment.id }
        timelineVM.timelineCreatedCommitmentIds.remove(commitment.id)
    }

    /// Remove commitment (cascades down to children, NOT up to parents)
    func removeCommitment(_ commitment: Commitment) async {
        do {
            try await deleteCommitmentWithDescendants(commitment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reschedule a commitment to a new date and/or timeframe
    /// Only the parent's commitment moves - subtask commitments stay at their original dates
    /// Returns true if successful, false if section limit exceeded
    func rescheduleCommitment(_ commitment: Commitment, to newDate: Date, newTimeframe: Timeframe) async -> Bool {
        // Check section limits for Focus section at destination
        if commitment.section == .focus {
            let canAdd = canAddToFocusSection(timeframe: newTimeframe, date: newDate, excludingCommitmentId: commitment.id)
            if !canAdd {
                errorMessage = "Focus section is full at destination (\(Section.focus.maxTasks(for: newTimeframe)!) max)"
                return false
            }
        }

        do {
            // Update commitment with new date and timeframe (subtask commitments stay)
            var updatedCommitment = commitment
            updatedCommitment.commitmentDate = newDate
            updatedCommitment.timeframe = newTimeframe

            try await commitmentRepository.updateCommitment(updatedCommitment)

            // Refresh to update view
            await fetchCommitments()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Check if Focus section has room at a specific date/timeframe
    /// Excludes a commitment ID to allow rescheduling within same section
    private func canAddToFocusSection(timeframe: Timeframe, date: Date, excludingCommitmentId: UUID) -> Bool {
        // Count existing Focus commitments at destination (excluding the one being moved)
        let existingCount = commitments.filter {
            $0.section == .focus &&
            $0.timeframe == timeframe &&
            isSameTimeframe($0.commitmentDate, timeframe: timeframe, selectedDate: date) &&
            $0.id != excludingCommitmentId
        }.count

        let maxAllowed = Section.focus.maxTasks(for: timeframe) ?? Int.max
        return existingCount < maxAllowed
    }

    /// Push commitment to next period (tomorrow, next week, next month, next year)
    /// Returns true if successful, false if section limit exceeded
    func pushCommitmentToNext(_ commitment: Commitment) async -> Bool {
        let calendar = Calendar.current
        let newDate: Date?

        switch commitment.timeframe {
        case .daily:
            newDate = calendar.date(byAdding: .day, value: 1, to: commitment.commitmentDate)
        case .weekly:
            newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: commitment.commitmentDate)
        case .monthly:
            newDate = calendar.date(byAdding: .month, value: 1, to: commitment.commitmentDate)
        case .yearly:
            newDate = calendar.date(byAdding: .year, value: 1, to: commitment.commitmentDate)
        }

        guard let nextDate = newDate else { return false }
        return await rescheduleCommitment(commitment, to: nextDate, newTimeframe: commitment.timeframe)
    }

    /// Move a commitment to a different section (Focus <-> Extra)
    /// Returns true if successful, false if section limit exceeded
    func moveCommitmentToSection(_ commitment: Commitment, to targetSection: Section) async -> Bool {
        // Skip if already in target section
        guard commitment.section != targetSection else { return true }

        // Check section limits for Focus
        if targetSection == .focus {
            guard canAddTask(to: .focus, timeframe: commitment.timeframe, date: commitment.commitmentDate) else {
                errorMessage = "Focus section is full (\(Section.focus.maxTasks(for: commitment.timeframe)!) max)"
                return false
            }
        }

        // Update commitment
        var updatedCommitment = commitment
        updatedCommitment.section = targetSection

        do {
            try await commitmentRepository.updateCommitment(updatedCommitment)

            // Update local state
            if let index = commitments.firstIndex(where: { $0.id == commitment.id }) {
                commitments[index] = updatedCommitment
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Drag Reorder Methods

    /// Get commitments for a section filtered to current timeframe/date, by completion state
    private func commitmentsForSection(_ section: Section, completed: Bool) -> [Commitment] {
        let filtered = commitments.filter { commitment in
            commitment.section == section &&
            commitment.parentCommitmentId == nil &&
            isSameTimeframe(commitment.commitmentDate, timeframe: selectedTimeframe, selectedDate: selectedDate) &&
            (tasksMap[commitment.taskId]?.isCompleted ?? false) == completed
        }
        return completed ? filtered : filtered.sorted { $0.sortOrder < $1.sortOrder }
    }

    func uncompletedCommitmentsForSection(_ section: Section) -> [Commitment] {
        commitmentsForSection(section, completed: false)
    }

    func completedCommitmentsForSection(_ section: Section) -> [Commitment] {
        commitmentsForSection(section, completed: true)
    }

    // MARK: - Flat Display Items

    var flattenedDisplayItems: [FocusFlatDisplayItem] {
        var result: [FocusFlatDisplayItem] = []

        let focusUncompleted = uncompletedCommitmentsForSection(.focus)
        let focusCompleted = completedCommitmentsForSection(.focus)
        let extraUncompleted = uncompletedCommitmentsForSection(.extra)
        let extraCompleted = completedCommitmentsForSection(.extra)

        // -- Focus section --
        result.append(.sectionHeader(.focus))

        if focusUncompleted.isEmpty && focusCompleted.isEmpty {
            result.append(.emptyState(.focus))
        } else if focusUncompleted.isEmpty && !focusCompleted.isEmpty && !isFocusDoneCollapsing {
            result.append(.allDoneState)
        }

        for c in focusUncompleted {
            result.append(.commitment(c))
            if expandedTasks.contains(c.taskId) {
                for subtask in getUncompletedSubtasks(for: c.taskId) {
                    result.append(.subtask(subtask, parentCommitment: c))
                }
                for subtask in getCompletedSubtasks(for: c.taskId) {
                    result.append(.subtask(subtask, parentCommitment: c))
                }
                result.append(.addSubtaskRow(parentId: c.taskId, parentCommitment: c))
            }
        }

        if isFocusDoneExpanded || !focusUncompleted.isEmpty || isFocusDoneCollapsing {
            for c in focusCompleted where !focusDoneHiddenIds.contains(c.id) {
                result.append(.completedCommitment(c))
            }
        }

        // During collapse, use a FIXED spacer matching the post-collapse layout.
        // This prevents discrete jumps — Extra section glides smoothly as items disappear.
        if isFocusDoneCollapsing {
            let focusRowCount = focusCompleted.count
            if focusRowCount > 0 && focusRowCount < 4 {
                let spacerHeight = CGFloat(4 - focusRowCount) * 48
                result.append(.focusSpacer(spacerHeight))
            }
        } else {
            // When all tasks are completed, no spacer — Extra sits right below
            // with the same natural margin whether 1 or 5 items are done.
            let allCompleted = focusUncompleted.isEmpty && !focusCompleted.isEmpty
            if !allCompleted {
                // Ensure focus section has minimum height of ~4 rows (skip when empty state is shown)
                let focusRowCount = focusUncompleted.count + focusCompleted.count
                if focusRowCount > 0 && focusRowCount < 4 {
                    let spacerHeight = CGFloat(4 - focusRowCount) * 48
                    result.append(.focusSpacer(spacerHeight))
                }
            }
        }

        // -- Extra section --
        result.append(.sectionHeader(.extra))

        if !isSectionCollapsed(.extra) {
            if extraUncompleted.isEmpty && extraCompleted.isEmpty {
                result.append(.emptyState(.extra))
            }

            for c in extraUncompleted {
                result.append(.commitment(c))
                if expandedTasks.contains(c.taskId) {
                    for subtask in getUncompletedSubtasks(for: c.taskId) {
                        result.append(.subtask(subtask, parentCommitment: c))
                    }
                    for subtask in getCompletedSubtasks(for: c.taskId) {
                        result.append(.subtask(subtask, parentCommitment: c))
                    }
                    result.append(.addSubtaskRow(parentId: c.taskId, parentCommitment: c))
                }
            }

            if !extraCompleted.isEmpty {
                result.append(.donePill)
            }

        }

        return result
    }

    // MARK: - Focus Section Config

    func focusConfig(for section: Section) -> FocusSectionConfig {
        guard section == .focus else {
            return FocusSectionConfig(
                taskFont: .sf(.body),
                verticalPadding: 8,
                containerMinHeight: 0,
                completedTaskFont: .sf(.subheadline),
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        }

        // Fixed layout for focus section — font size never changes
        return FocusSectionConfig(
            taskFont: .sf(.title3),
            verticalPadding: 14,
            containerMinHeight: 230,
            completedTaskFont: .sf(.subheadline),
            completedVerticalPadding: 6,
            completedOpacity: 0.45
        )
    }

    // MARK: - Flat Move Handler

    /// Handle .onMove from the flat ForEach — supports commitment reorder, cross-section moves, and subtask reorder.
    func handleFlatMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedDisplayItems
        guard let fromIdx = source.first else { return }

        // Check if it's a subtask move
        if case .subtask(let movedSubtask, let parentCommitment) = flat[fromIdx] {
            handleSubtaskMove(movedSubtask: movedSubtask, parentCommitment: parentCommitment, flat: flat, fromIdx: fromIdx, destination: destination)
            return
        }

        // Only .commitment items can be moved (besides subtasks handled above)
        guard case .commitment(let movedCommitment) = flat[fromIdx] else { return }

        let sourceSection = movedCommitment.section

        // Determine destination section by scanning backward for nearest section header
        var destSection: Section = .focus
        for i in stride(from: min(destination, flat.count - 1), through: 0, by: -1) {
            if case .sectionHeader(let section) = flat[i] {
                destSection = section
                break
            }
        }

        if sourceSection == destSection {
            // -- Same-section reorder --
            let sectionCommitments = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, commitment: Commitment)? in
                if case .commitment(let c) = item, c.section == sourceSection {
                    return (i, c)
                }
                return nil
            }

            guard let commitmentFrom = sectionCommitments.firstIndex(where: { $0.commitment.id == movedCommitment.id }) else { return }

            var commitmentTo = sectionCommitments.count
            for (ci, entry) in sectionCommitments.enumerated() {
                if destination <= entry.flatIdx {
                    commitmentTo = ci
                    break
                }
            }
            if commitmentTo > commitmentFrom { commitmentTo = min(commitmentTo, sectionCommitments.count) }

            guard commitmentFrom != commitmentTo && commitmentFrom + 1 != commitmentTo else { return }

            var uncompleted = uncompletedCommitmentsForSection(sourceSection)
            uncompleted.move(fromOffsets: IndexSet(integer: commitmentFrom), toOffset: commitmentTo)

            // Reassign sort orders
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, c) in uncompleted.enumerated() {
                if let mainIndex = commitments.firstIndex(where: { $0.id == c.id }) {
                    commitments[mainIndex].sortOrder = index
                }
                updates.append((id: c.id, sortOrder: index))
            }
            _Concurrency.Task { await persistCommitmentSortOrders(updates) }

        } else {
            // -- Cross-section move --
            if destSection == .focus {
                guard canAddTask(to: .focus, timeframe: movedCommitment.timeframe, date: movedCommitment.commitmentDate) else { return }
            }

            // Find insertion index among destination section's uncompleted commitments
            let destCommitments = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, commitment: Commitment)? in
                if case .commitment(let c) = item, c.section == destSection {
                    return (i, c)
                }
                return nil
            }

            var insertIdx = destCommitments.count
            for (ci, entry) in destCommitments.enumerated() {
                if destination <= entry.flatIdx {
                    insertIdx = ci
                    break
                }
            }

            moveCommitmentToSectionAtIndex(movedCommitment, to: destSection, atIndex: insertIdx)
        }
    }

    /// Handle subtask reorder within the same parent
    private func handleSubtaskMove(movedSubtask: FocusTask, parentCommitment: Commitment, flat: [FocusFlatDisplayItem], fromIdx: Int, destination: Int) {
        let parentId = parentCommitment.taskId

        // Find parent commitment's flat index
        guard let parentFlatIdx = flat.firstIndex(where: {
            if case .commitment(let c) = $0 { return c.id == parentCommitment.id }
            return false
        }) else { return }

        // Find section bounds: next commitment/sectionHeader or end of array
        let sectionEnd = flat[(parentFlatIdx + 1)...].firstIndex(where: {
            if case .commitment = $0 { return true }
            if case .completedCommitment = $0 { return true }
            if case .sectionHeader = $0 { return true }
            if case .emptyState = $0 { return true }
            if case .donePill = $0 { return true }
            if case .allDoneState = $0 { return true }
            if case .focusSpacer = $0 { return true }
            return false
        }) ?? flat.count

        // Reject cross-parent moves
        guard destination > parentFlatIdx && destination <= sectionEnd else { return }

        // Map flat indices to sibling-only (uncompleted) indices
        let siblingIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
            if case .subtask(let t, _) = item, t.parentTaskId == parentId, !t.isCompleted { return (i, t) }
            return nil
        }

        guard let siblingFrom = siblingIndices.firstIndex(where: { $0.task.id == movedSubtask.id }) else { return }

        // Map flat destination to sibling-only destination
        var siblingTo = siblingIndices.count
        for (si, entry) in siblingIndices.enumerated() {
            if destination <= entry.flatIdx {
                siblingTo = si
                break
            }
        }
        if siblingTo > siblingFrom { siblingTo = min(siblingTo, siblingIndices.count) }

        guard siblingFrom != siblingTo && siblingFrom + 1 != siblingTo else { return }

        // Apply move on uncompleted subtasks
        guard var allChildren = subtasksMap[parentId] else { return }
        var uncompleted = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

        uncompleted.move(fromOffsets: IndexSet(integer: siblingFrom), toOffset: siblingTo)

        // Write sort orders back into full children array
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, child) in uncompleted.enumerated() {
            if let mapIndex = allChildren.firstIndex(where: { $0.id == child.id }) {
                allChildren[mapIndex].sortOrder = index
            }
            updates.append((id: child.id, sortOrder: index))
        }
        subtasksMap[parentId] = allChildren
        _Concurrency.Task { await persistSubtaskSortOrders(updates) }
    }

    /// Reorder a commitment within the same section
    func reorderCommitment(droppedId: UUID, targetId: UUID) {
        // Find both commitments
        guard let dropped = commitments.first(where: { $0.id == droppedId }),
              let target = commitments.first(where: { $0.id == targetId }),
              dropped.section == target.section else { return }

        var sectionCommitments = uncompletedCommitmentsForSection(dropped.section)

        guard let fromIndex = sectionCommitments.firstIndex(where: { $0.id == droppedId }),
              let toIndex = sectionCommitments.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return }

        let moved = sectionCommitments.remove(at: fromIndex)
        sectionCommitments.insert(moved, at: toIndex)

        // Reassign sort orders in the main commitments array
        for (index, commitment) in sectionCommitments.enumerated() {
            if let mainIndex = commitments.firstIndex(where: { $0.id == commitment.id }) {
                commitments[mainIndex].sortOrder = index
            }
        }

        // Persist in background
        let updates = sectionCommitments.enumerated().map { (index, c) in
            (id: c.id, sortOrder: index)
        }
        Task {
            await persistCommitmentSortOrders(updates)
        }
    }

    /// Move a commitment to a different section at a specific index
    func moveCommitmentToSectionAtIndex(_ commitment: Commitment, to targetSection: Section, atIndex: Int) {
        guard commitment.section != targetSection else { return }

        // Validate Focus section capacity
        if targetSection == .focus {
            guard canAddTask(to: .focus, timeframe: commitment.timeframe, date: commitment.commitmentDate) else { return }
        }

        // Get source and target section lists
        var sourceList = uncompletedCommitmentsForSection(commitment.section)
        var targetList = uncompletedCommitmentsForSection(targetSection)

        // Remove from source
        sourceList.removeAll { $0.id == commitment.id }

        // Insert into target at the specified index (clamped)
        let insertIndex = min(atIndex, targetList.count)
        var movedCommitment = commitment
        movedCommitment.section = targetSection
        targetList.insert(movedCommitment, at: insertIndex)

        // Update in main commitments array
        if let mainIndex = commitments.firstIndex(where: { $0.id == commitment.id }) {
            commitments[mainIndex].section = targetSection
        }

        // Reassign sort orders for both sections
        for (index, c) in sourceList.enumerated() {
            if let mainIndex = commitments.firstIndex(where: { $0.id == c.id }) {
                commitments[mainIndex].sortOrder = index
            }
        }
        for (index, c) in targetList.enumerated() {
            if let mainIndex = commitments.firstIndex(where: { $0.id == c.id }) {
                commitments[mainIndex].sortOrder = index
            }
        }

        // Persist in background (include section so cross-section moves are saved)
        let allUpdates = sourceList.enumerated().map { (i, c) in (id: c.id, sortOrder: i, section: commitment.section) }
            + targetList.enumerated().map { (i, c) in (id: c.id, sortOrder: i, section: targetSection) }
        _Concurrency.Task { @MainActor in
            await persistCommitmentSortOrdersAndSections(allUpdates)
        }
    }

    /// Persist commitment sort orders to database
    private func persistCommitmentSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await commitmentRepository.updateCommitmentSortOrders(updates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist commitment sort orders and sections to database
    private func persistCommitmentSortOrdersAndSections(_ updates: [(id: UUID, sortOrder: Int, section: Section)]) async {
        do {
            try await commitmentRepository.updateCommitmentSortOrdersAndSections(updates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist subtask sort orders to database
    private func persistSubtaskSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await taskRepository.updateSortOrders(updates)
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

    /// Toggle section collapsed state (Extra section only)
    func toggleSectionCollapsed(_ section: Section) {
        if section == .extra {
            isExtraSectionCollapsed.toggle()
        }
    }

    /// Check if section is collapsed
    func isSectionCollapsed(_ section: Section) -> Bool {
        section == .extra ? isExtraSectionCollapsed : false
    }

    /// Toggle Done subsection collapsed state
    func toggleDoneSubsectionCollapsed() {
        isDoneSubsectionCollapsed.toggle()
    }

    /// Create a new task and immediately commit it to the current timeframe/date/section
    @discardableResult
    func createTaskWithCommitment(title: String, section: Section) async -> (taskId: UUID, commitment: Commitment)? {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return nil
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        // Check section limits for Focus
        if section == .focus && !canAddTask(to: .focus) {
            errorMessage = "Focus section is full"
            return nil
        }

        do {
            // Create the task
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false,
                isInLog: true
            )
            let createdTask = try await taskRepository.createTask(newTask)

            // Create commitment for current timeframe/date
            let maxSort = commitments
                .filter { $0.section == section &&
                    isSameTimeframe($0.commitmentDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let commitment = Commitment(
                userId: userId,
                taskId: createdTask.id,
                timeframe: selectedTimeframe,
                section: section,
                commitmentDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdCommitment = try await commitmentRepository.createCommitment(commitment)

            // Update local state
            tasksMap[createdTask.id] = createdTask
            commitments.append(createdCommitment)

            return (taskId: createdTask.id, commitment: createdCommitment)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Create task + commitment + subtasks atomically, updating view state once at the end
    func createTaskWithSubtasks(title: String, section: Section, subtaskTitles: [String]) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if section == .focus && !canAddTask(to: .focus) {
            errorMessage = "Focus section is full"
            return
        }

        do {
            // 1. Create task
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false,
                isInLog: true
            )
            let createdTask = try await taskRepository.createTask(newTask)

            // 2. Create commitment
            let maxSort = commitments
                .filter { $0.section == section &&
                    isSameTimeframe($0.commitmentDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let commitment = Commitment(
                userId: userId,
                taskId: createdTask.id,
                timeframe: selectedTimeframe,
                section: section,
                commitmentDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdCommitment = try await commitmentRepository.createCommitment(commitment)

            // 3. Create subtasks (all via repository, no view updates yet)
            var createdSubtasks: [FocusTask] = []
            for subtaskTitle in subtaskTitles where !subtaskTitle.isEmpty {
                let subtask = try await taskRepository.createSubtask(
                    title: subtaskTitle,
                    parentTaskId: createdTask.id,
                    userId: userId
                )
                createdSubtasks.append(subtask)
            }

            // 4. Single batch view update — one coordinated animation
            withAnimation(.easeInOut(duration: 0.3)) {
                tasksMap[createdTask.id] = createdTask
                commitments.append(createdCommitment)
                if !createdSubtasks.isEmpty {
                    subtasksMap[createdTask.id] = createdSubtasks
                    for subtask in createdSubtasks {
                        tasksMap[subtask.id] = subtask
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle task completion with cascade to subtasks
    func toggleTaskCompletion(_ task: FocusTask) async {
        do {
            var didRestoreSubtasks = false

            if task.isCompleted {
                // Uncompleting parent - restore previous subtask states
                try await taskRepository.uncompleteTask(id: task.id)

                let currentTask = tasksMap[task.id]
                if let previousStates = currentTask?.previousCompletionState {
                    try await taskRepository.restoreSubtaskStates(parentId: task.id, completionStates: previousStates)
                    // Refresh subtasks from DB
                    let refreshed = try await taskRepository.fetchSubtasks(parentId: task.id)
                    if !refreshed.isEmpty {
                        subtasksMap[task.id] = refreshed
                    }
                    didRestoreSubtasks = true
                }
            } else {
                // Completing parent - save subtask states and complete all
                let subtasks = subtasksMap[task.id] ?? []
                let previousStates = subtasks.map { $0.isCompleted }

                // Save previous states to parent task
                if var parentTask = tasksMap[task.id] {
                    parentTask.previousCompletionState = previousStates
                    try await taskRepository.updateTask(parentTask)
                    tasksMap[task.id] = parentTask
                }

                // Complete parent and all subtasks
                try await taskRepository.completeTask(id: task.id)
                if !subtasks.isEmpty {
                    try await taskRepository.completeSubtasks(parentId: task.id)
                    if var localSubtasks = subtasksMap[task.id] {
                        for i in localSubtasks.indices {
                            localSubtasks[i].isCompleted = true
                            localSubtasks[i].completedDate = Date()
                        }
                        subtasksMap[task.id] = localSubtasks
                    }
                    didRestoreSubtasks = true
                }
            }

            // Update local parent task state
            if var updatedTask = tasksMap[task.id] {
                updatedTask.isCompleted.toggle()
                if updatedTask.isCompleted {
                    updatedTask.completedDate = Date()
                } else {
                    updatedTask.completedDate = nil
                }

                // Pre-check: will this completion leave Focus with no uncompleted items?
                // (Before updating tasksMap, this task is still "uncompleted" in the filter)
                let willTriggerCollapse = updatedTask.isCompleted &&
                    uncompletedCommitmentsForSection(.focus).allSatisfy { $0.taskId == task.id }

                withAnimation(.easeInOut(duration: 0.3)) {
                    tasksMap[task.id] = updatedTask
                    // Set collapse flag in SAME animation to prevent intermediate allDoneState flash
                    if willTriggerCollapse {
                        isFocusDoneCollapsing = true
                    }
                }
                // Notify other views
                postTaskCompletionNotification(
                    taskId: task.id,
                    isCompleted: updatedTask.isCompleted,
                    completedDate: updatedTask.completedDate,
                    subtasksChanged: didRestoreSubtasks
                )

                // Auto-collapse Focus completed list when last task is checked
                if willTriggerCollapse {
                    triggerFocusDoneCollapse()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Staggered collapse animation: items slide up one by one, then checkmark pulses
    func triggerFocusDoneCollapse() {
        let completed = completedCommitmentsForSection(.focus)
        guard !completed.isEmpty else {
            isFocusDoneExpanded = false
            return
        }

        // Only animate isFocusDoneCollapsing if not already set
        // (callers may set it in the same animation block as the task state change)
        if !isFocusDoneCollapsing {
            withAnimation(.easeInOut(duration: 0.3)) {
                isFocusDoneCollapsing = true
            }
        }
        focusDoneHiddenIds = []

        // Brief pause to let the completion state (strikethrough/opacity) settle visually
        let initialDelay: Double = 0.5

        // Stagger remove each item from bottom to top
        let reversed = Array(completed.reversed())
        for (index, commitment) in reversed.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay + Double(index) * 0.3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    _ = self.focusDoneHiddenIds.insert(commitment.id)
                }
            }
        }

        // After all items removed, show allDoneState and pulse checkmark
        let totalDelay = initialDelay + Double(reversed.count) * 0.3 + 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            // Haptic + pulse fire immediately as allDoneState appears
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.allDoneCheckPulse = true

            withAnimation(.easeInOut(duration: 0.3)) {
                self.isFocusDoneCollapsing = false
                self.isFocusDoneExpanded = false
                self.focusDoneHiddenIds = []
            }

            // Snap checkmark back after the pulse
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.allDoneCheckPulse = false
                }
            }
        }
    }

    /// Toggle subtask completion - auto-completes parent when all same-timeframe subtasks done
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        // Capture BEFORE toggle for potential parent auto-complete restore
        let preToggleStates = (subtasksMap[parentId] ?? []).map { $0.isCompleted }
        do {
            if subtask.isCompleted {
                try await taskRepository.uncompleteTask(id: subtask.id)
            } else {
                try await taskRepository.completeTask(id: subtask.id)
            }

            // Update local subtask state
            if var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                subtasks[index].isCompleted.toggle()
                if subtasks[index].isCompleted {
                    subtasks[index].completedDate = Date()
                } else {
                    subtasks[index].completedDate = nil
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    subtasksMap[parentId] = subtasks
                }

                // Notify other views about subtask change
                postTaskCompletionNotification(
                    taskId: subtask.id,
                    isCompleted: subtasks[index].isCompleted,
                    completedDate: subtasks[index].completedDate
                )

                // Check auto-completion using same-timeframe logic
                let shouldAutoComplete = checkShouldAutoCompleteParent(parentId: parentId, subtasks: subtasks)

                if shouldAutoComplete {
                    if var parentTask = tasksMap[parentId], !parentTask.isCompleted {
                        parentTask.previousCompletionState = preToggleStates
                        try await taskRepository.updateTask(parentTask)
                        try await taskRepository.completeTask(id: parentId)
                        parentTask.isCompleted = true
                        parentTask.completedDate = Date()

                        // Pre-check: will completing this parent leave Focus with no uncompleted items?
                        let willTriggerCollapse = uncompletedCommitmentsForSection(.focus)
                            .allSatisfy { $0.taskId == parentId }

                        withAnimation(.easeInOut(duration: 0.3)) {
                            tasksMap[parentId] = parentTask
                            if willTriggerCollapse {
                                isFocusDoneCollapsing = true
                            }
                        }
                        postTaskCompletionNotification(
                            taskId: parentId,
                            isCompleted: true,
                            completedDate: parentTask.completedDate
                        )
                        // Auto-collapse Focus completed list when last task is checked
                        if willTriggerCollapse {
                            triggerFocusDoneCollapse()
                        }
                    }
                } else {
                    // If not all relevant subtasks complete and parent is completed, uncomplete parent
                    if var parentTask = tasksMap[parentId], parentTask.isCompleted {
                        try await taskRepository.uncompleteTask(id: parentId)
                        parentTask.isCompleted = false
                        parentTask.completedDate = nil
                        withAnimation(.easeInOut(duration: 0.3)) {
                            tasksMap[parentId] = parentTask
                        }
                        postTaskCompletionNotification(
                            taskId: parentId,
                            isCompleted: false,
                            completedDate: nil
                        )
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Check if parent should auto-complete based on same-timeframe subtasks only
    /// Rule: Only count subtasks that are at the same timeframe level as the parent
    /// Subtasks broken down to lower timeframes don't count toward origin completion
    private func checkShouldAutoCompleteParent(parentId: UUID, subtasks: [FocusTask]) -> Bool {
        guard !subtasks.isEmpty else { return false }

        // Get parent's commitment at the current timeframe
        let parentCommitment = commitments.first {
            $0.taskId == parentId && $0.timeframe == selectedTimeframe
        }

        // Filter subtasks that count toward auto-completion:
        // 1. Subtasks with NO commitment (followers), OR
        // 2. Subtasks with commitment at SAME timeframe as parent
        let relevantSubtasks = subtasks.filter { subtask in
            let subtaskCommitment = commitments.first { $0.taskId == subtask.id }

            if subtaskCommitment == nil {
                return true  // Follower subtask - counts toward parent completion
            }

            // Only count if same timeframe as parent
            return subtaskCommitment?.timeframe == parentCommitment?.timeframe
        }

        // If no relevant subtasks, don't auto-complete
        guard !relevantSubtasks.isEmpty else { return false }

        // Auto-complete if all relevant subtasks are complete
        return relevantSubtasks.allSatisfy { $0.isCompleted }
    }

    // MARK: - Commit Methods (Trickle-Down)

    /// Fetch child commitments for all current commitments recursively
    func fetchChildCommitments() async {
        for commitment in commitments where commitment.canBreakdown {
            await fetchChildrenRecursively(for: commitment)
        }
    }

    /// Recursively fetch children and grandchildren
    private func fetchChildrenRecursively(for commitment: Commitment) async {
        do {
            let children = try await commitmentRepository.fetchChildCommitments(
                parentId: commitment.id
            )
            childCommitmentsMap[commitment.id] = children

            // Recursively fetch grandchildren for children that can break down
            for child in children where child.canBreakdown {
                await fetchChildrenRecursively(for: child)
            }
        } catch {
            print("Error fetching children for \(commitment.id): \(error)")
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

    /// Commit a task to a specific date and timeframe
    func commitToTimeframe(_ commitment: Commitment, toDate date: Date, targetTimeframe: Timeframe) async {
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

    /// Commit a subtask to a target timeframe (creates commitment for subtask that doesn't have one)
    func commitSubtask(_ subtask: FocusTask, parentCommitment: Commitment, toDate: Date, targetTimeframe: Timeframe) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        do {
            // Create commitment for the subtask at target timeframe
            let subtaskCommitment = Commitment(
                userId: userId,
                taskId: subtask.id,
                timeframe: targetTimeframe,
                section: parentCommitment.section,
                commitmentDate: toDate,
                sortOrder: 0,
                parentCommitmentId: parentCommitment.id
            )
            let created = try await commitmentRepository.createCommitment(subtaskCommitment)

            // Update local state
            commitments.append(created)
            tasksMap[subtask.id] = subtask

            // Track as child of parent commitment
            if var children = childCommitmentsMap[parentCommitment.id] {
                children.append(created)
                childCommitmentsMap[parentCommitment.id] = children
            } else {
                childCommitmentsMap[parentCommitment.id] = [created]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Calculate available slots for committing to any target timeframe
    func availableSlotsForCommit(_ commitment: Commitment, targetTimeframe: Timeframe) -> [Date] {
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
