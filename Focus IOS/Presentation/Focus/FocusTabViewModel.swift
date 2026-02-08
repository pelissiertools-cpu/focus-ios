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
    @Published var showCommitSheet = false
    @Published var selectedCommitmentForCommit: Commitment?

    // Subtask commit state (for committing subtasks that don't have their own commitment)
    @Published var selectedSubtaskForCommit: FocusTask?
    @Published var selectedParentCommitmentForSubtaskCommit: Commitment?
    @Published var showSubtaskCommitSheet = false

    // Section collapse and add task state
    @Published var isExtraSectionCollapsed: Bool = false
    @Published var isDoneSubsectionCollapsed: Bool = true  // Closed by default
    @Published var showAddTaskSheet: Bool = false
    @Published var addTaskSection: Section = .extra

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

                    // Fetch subtasks for any task that has a commitment in this view
                    // This includes subtasks that have been broken down and now act as parents
                    let subtasks = try await taskRepository.fetchSubtasks(parentId: taskId)
                    if !subtasks.isEmpty {
                        subtasksMap[taskId] = subtasks
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

    /// Delete a task - only hard-deletes if task originated in Focus (not Library)
    func deleteTask(_ task: FocusTask) async {
        // For Library-origin tasks, use removeCommitment() instead
        // This method should only hard-delete Focus-origin tasks
        guard !task.isInLibrary else {
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

    /// Create a new subtask with a commitment at the parent's timeframe (Focus view use case)
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
    private func deleteCommitmentWithDescendants(_ commitment: Commitment) async throws {
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
    }

    /// Remove commitment (cascades down to children, NOT up to parents)
    func removeCommitment(_ commitment: Commitment) async {
        do {
            try await deleteCommitmentWithDescendants(commitment)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    func createTaskWithCommitment(title: String, section: Section) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        // Check section limits for Focus
        if section == .focus && !canAddTask(to: .focus) {
            errorMessage = "Focus section is full"
            return
        }

        do {
            // Create the task
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false,
                isInLibrary: true
            )
            let createdTask = try await taskRepository.createTask(newTask)

            // Create commitment for current timeframe/date
            let commitment = Commitment(
                userId: userId,
                taskId: createdTask.id,
                timeframe: selectedTimeframe,
                section: section,
                commitmentDate: selectedDate,
                sortOrder: 0
            )
            let createdCommitment = try await commitmentRepository.createCommitment(commitment)

            // Update local state
            tasksMap[createdTask.id] = createdTask
            commitments.append(createdCommitment)
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Toggle subtask completion - auto-completes parent when all same-timeframe subtasks done
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
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
                subtasksMap[parentId] = subtasks

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
                        parentTask.previousCompletionState = subtasks.map { $0.isCompleted }
                        try await taskRepository.completeTask(id: parentId)
                        parentTask.isCompleted = true
                        parentTask.completedDate = Date()
                        tasksMap[parentId] = parentTask
                        postTaskCompletionNotification(
                            taskId: parentId,
                            isCompleted: true,
                            completedDate: parentTask.completedDate
                        )
                    }
                } else {
                    // If not all relevant subtasks complete and parent is completed, uncomplete parent
                    if var parentTask = tasksMap[parentId], parentTask.isCompleted {
                        try await taskRepository.uncompleteTask(id: parentId)
                        parentTask.isCompleted = false
                        parentTask.completedDate = nil
                        tasksMap[parentId] = parentTask
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
