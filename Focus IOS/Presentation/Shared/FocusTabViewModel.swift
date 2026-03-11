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
    case schedule(Schedule)           // uncompleted — movable
    case completedSchedule(Schedule)   // completed — not movable
    case subtask(FocusTask, parentSchedule: Schedule)
    case addSubtaskRow(parentId: UUID, parentSchedule: Schedule)
    case addFocusRow
    case emptyState(Section)
    case allDoneState
    case donePill
    case focusSpacer(CGFloat)
    case rollupSectionHeader
    case rollupDayHeader(Date, String)   // date = group anchor, String = display label
    case rollupSchedule(Schedule)
    case todoPriorityHeader(Priority)
    case addTodoTaskRow(Priority)

    var id: String {
        switch self {
        case .sectionHeader(let section):
            return "header-\(section.rawValue)"
        case .schedule(let c):
            return c.id.uuidString
        case .completedSchedule(let c):
            return c.id.uuidString  // Same ID as .schedule for smooth in-place transition
        case .subtask(let task, _):
            return "subtask-\(task.id.uuidString)"
        case .addSubtaskRow(let parentId, _):
            return "add-subtask-\(parentId.uuidString)"
        case .addFocusRow:
            return "add-focus"
        case .emptyState(let section):
            return "empty-\(section.rawValue)"
        case .allDoneState:
            return "all-done"
        case .donePill:
            return "done-pill"
        case .focusSpacer:
            return "focus-spacer"
        case .rollupSectionHeader:
            return "rollup-section-header"
        case .rollupDayHeader(let date, _):
            return "rollup-header-\(Int(date.timeIntervalSince1970))"
        case .rollupSchedule(let c):
            return "rollup-\(c.id.uuidString)"
        case .todoPriorityHeader(let priority):
            return "todo-priority-\(priority.rawValue)"
        case .addTodoTaskRow(let priority):
            return "add-todo-task-\(priority.rawValue)"
        }
    }
}

@MainActor
class FocusTabViewModel: ObservableObject, TaskEditingViewModel {
    @Published var schedules: [Schedule] = []
    @Published var rollupSchedules: [Schedule] = []
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
    @Published var childSchedulesMap: [UUID: [Schedule]] = [:]  // parentId -> children
    @Published var showScheduleSheet = false
    @Published var selectedScheduleForSchedule: Schedule?

    // Reschedule state (triggered from context menu)
    @Published var selectedScheduleForReschedule: Schedule?
    @Published var showRescheduleSheet = false

    // Subtask schedule state (for scheduling subtasks that don't have their own schedule)
    @Published var selectedSubtaskForSchedule: FocusTask?
    @Published var selectedParentScheduleForSubtaskSchedule: Schedule?
    @Published var showSubtaskScheduleSheet = false

    // Day Assignment state (assign specific days to weekly/monthly/yearly schedules)
    @Published var selectedScheduleForDayAssignment: Schedule?
    @Published var showDayAssignmentSheet = false

    // Section collapse and add task state
    @Published var isFocusSectionCollapsed: Bool = false
    @Published var isTodoSectionCollapsed: Bool = false
    @Published var isRollupSectionCollapsed: Bool = true
    @Published var expandedRollupGroups: Set<Date> = []  // All groups collapsed by default
    @Published var isDoneSubsectionCollapsed: Bool = true  // Closed by default
    @Published var isFocusDoneExpanded: Bool = false  // Focus "All Done" completed list hidden by default
    @Published var isFocusDoneCollapsing: Bool = false  // True during staggered collapse animation
    @Published var focusDoneHiddenIds: Set<UUID> = []  // IDs being animated out during collapse
    @Published var allDoneCheckPulse: Bool = false  // Checkmark scale pulse after collapse
    @Published var showAddTaskSheet: Bool = false
    @Published var addTaskSection: Section = .todo

    // To-Do priority sort state
    @Published var todoPrioritySortEnabled: Bool = true
    @Published var todoPrioritySortDirection: SortDirection = .highestFirst
    @Published var collapsedTodoPriorities: Set<Priority> = []

    private let scheduleRepository: ScheduleRepository
    private let taskRepository: TaskRepository
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(scheduleRepository: ScheduleRepository = ScheduleRepository(),
         taskRepository: TaskRepository = TaskRepository(),
         authService: AuthService) {
        self.scheduleRepository = scheduleRepository
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

    /// Fetch schedules for selected timeframe and date
    func fetchSchedules() async {
        // Only show loading spinner on initial load (no cached data yet)
        let isInitialLoad = !hasLoadedInitialData
        if isInitialLoad {
            isLoading = true
        }
        errorMessage = nil

        do {
            // Fetch both focus and to-do sections
            let focusSchedules = try await scheduleRepository.fetchSchedules(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .focus
            )
            let todoSchedules = try await scheduleRepository.fetchSchedules(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .todo
            )

            self.schedules = focusSchedules + todoSchedules

            // Fetch rollup (child timeframe items within current period)
            if selectedTimeframe != .daily {
                rollupSchedules = try await scheduleRepository.fetchRollupSchedules(
                    parentTimeframe: selectedTimeframe,
                    date: selectedDate
                )
            } else {
                rollupSchedules = []
            }

            // Fetch associated tasks (schedules + rollup batched in one call)
            await fetchTasksForSchedules()

            // Fetch child schedules for trickle-down display
            await fetchChildSchedules()

            hasLoadedInitialData = true
            isLoading = false
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    /// Fetch task details for all schedules
    private func fetchTasksForSchedules() async {
        let taskIds = Array(Set((schedules + rollupSchedules).map { $0.taskId }))
        guard !taskIds.isEmpty else { return }

        do {
            // Fetch only the tasks referenced by schedules
            let tasks = try await taskRepository.fetchTasksByIds(taskIds)

            for task in tasks {
                tasksMap[task.id] = task
            }

            // Batch-fetch all subtasks in a single query instead of N+1
            let allSubtasks = try await taskRepository.fetchSubtasksByParentIds(taskIds)
            for (parentId, subtasks) in allSubtasks {
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
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

    /// Update a task's note (description)
    func updateTaskNote(_ task: FocusTask, newNote: String?) async {
        do {
            var updatedTask = task
            updatedTask.description = newNote
            updatedTask.modifiedDate = Date()

            try await taskRepository.updateTask(updatedTask)

            if tasksMap[task.id] != nil {
                tasksMap[task.id]?.description = newNote
                tasksMap[task.id]?.modifiedDate = Date()
            }

            if let parentId = task.parentTaskId,
               var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                subtasks[index].description = newNote
                subtasks[index].modifiedDate = Date()
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a task - only hard-deletes non-library items (e.g. sections).
    /// Library tasks should be unscheduled via removeSchedule() instead.
    func deleteTask(_ task: FocusTask) async {
        guard !task.isInLibrary else {
            return
        }

        do {
            // Remove all schedules for this task (with cascade)
            let taskSchedules = schedules.filter { $0.taskId == task.id }
            for schedule in taskSchedules {
                try await deleteScheduleWithDescendants(schedule)
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
    /// Removes ALL schedules for this task and its subtasks, then hard-deletes everything.
    func permanentlyDeleteTask(_ task: FocusTask) async {
        do {
            // Delete subtask schedules and subtasks
            let subtasks = subtasksMap[task.id] ?? []
            for subtask in subtasks {
                try await scheduleRepository.deleteSchedules(forTask: subtask.id)
                try await taskRepository.deleteTask(id: subtask.id)
            }

            // Delete ALL schedules for this task (covers all timeframes)
            try await scheduleRepository.deleteSchedules(forTask: task.id)

            // Delete the task itself
            try await taskRepository.deleteTask(id: task.id)

            // Clean up local state
            tasksMap.removeValue(forKey: task.id)
            subtasksMap.removeValue(forKey: task.id)
            for subtask in subtasks {
                tasksMap.removeValue(forKey: subtask.id)
            }
            let deletedTaskIds = Set([task.id] + subtasks.map { $0.id })
            schedules.removeAll { deletedTaskIds.contains($0.taskId) }
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

    /// Create a new subtask with a schedule at the parent's timeframe (breakdown use case)
    func createSubtask(title: String, parentId: UUID, parentSchedule: Schedule) async {
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

            // Create a schedule for this subtask at the parent's timeframe
            let subtaskSchedule = Schedule(
                userId: userId,
                taskId: newSubtask.id,
                timeframe: parentSchedule.timeframe,
                section: parentSchedule.section,
                scheduleDate: parentSchedule.scheduleDate,
                sortOrder: 0,
                parentScheduleId: parentSchedule.id
            )
            let created = try await scheduleRepository.createSchedule(subtaskSchedule)
            schedules.append(created)

            // Track as child of parent schedule
            if var children = childSchedulesMap[parentSchedule.id] {
                children.append(created)
                childSchedulesMap[parentSchedule.id] = children
            } else {
                childSchedulesMap[parentSchedule.id] = [created]
            }

            // Add subtask to tasksMap so it can be displayed independently
            tasksMap[newSubtask.id] = newSubtask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Check if schedule date matches selected timeframe and date
    func isSameTimeframe(_ scheduleDate: Date, timeframe: Timeframe, selectedDate: Date) -> Bool {
        var calendar = Calendar.current

        switch timeframe {
        case .daily:
            return calendar.isDate(scheduleDate, inSameDayAs: selectedDate)
        case .weekly:
            calendar.firstWeekday = 1 // Sunday
            let scheduleWeek = calendar.component(.weekOfYear, from: scheduleDate)
            let selectedWeek = calendar.component(.weekOfYear, from: selectedDate)
            let scheduleYear = calendar.component(.yearForWeekOfYear, from: scheduleDate)
            let selectedYear = calendar.component(.yearForWeekOfYear, from: selectedDate)
            return scheduleWeek == selectedWeek && scheduleYear == selectedYear
        case .monthly:
            let scheduleMonth = calendar.component(.month, from: scheduleDate)
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let scheduleYear = calendar.component(.year, from: scheduleDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return scheduleMonth == selectedMonth && scheduleYear == selectedYear
        case .yearly:
            let scheduleYear = calendar.component(.year, from: scheduleDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return scheduleYear == selectedYear
        }
    }

    /// Check if can add more tasks to section
    func canAddTask(to section: Section, timeframe: Timeframe? = nil, date: Date? = nil) -> Bool {
        let checkTimeframe = timeframe ?? selectedTimeframe
        let checkDate = date ?? selectedDate

        let currentCount = schedules.filter {
            $0.section == section &&
            $0.timeframe == checkTimeframe &&
            isSameTimeframe($0.scheduleDate, timeframe: checkTimeframe, selectedDate: checkDate)
        }.count

        let maxTasks = section.maxTasks(for: checkTimeframe)
        return maxTasks == nil || currentCount < maxTasks!
    }

    /// Get current task count for section
    func taskCount(for section: Section, timeframe: Timeframe? = nil, date: Date? = nil) -> Int {
        let checkTimeframe = timeframe ?? selectedTimeframe
        let checkDate = date ?? selectedDate

        return schedules.filter {
            $0.section == section &&
            $0.timeframe == checkTimeframe &&
            isSameTimeframe($0.scheduleDate, timeframe: checkTimeframe, selectedDate: checkDate)
        }.count
    }

    /// Recursively delete a schedule and all its descendants (cascade down)
    func deleteScheduleWithDescendants(_ schedule: Schedule) async throws {
        // First, recursively delete all children
        let children = childSchedulesMap[schedule.id] ?? []
        for child in children {
            try await deleteScheduleWithDescendants(child)
        }

        // Clean up local state for this schedule's children
        childSchedulesMap.removeValue(forKey: schedule.id)

        // Delete this schedule from database
        try await scheduleRepository.deleteSchedule(id: schedule.id)

        // Remove from local state
        schedules.removeAll { $0.id == schedule.id }
    }

    /// Clear scheduled time from a schedule (keep the schedule itself)
    func unscheduleSchedule(_ scheduleId: UUID) async {
        do {
            try await scheduleRepository.updateScheduleTime(id: scheduleId, scheduledTime: nil, durationMinutes: nil)
            if let index = schedules.firstIndex(where: { $0.id == scheduleId }) {
                schedules[index].scheduledTime = nil
                schedules[index].durationMinutes = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Remove schedule (cascades down to children, NOT up to parents)
    func removeSchedule(_ schedule: Schedule) async {
        do {
            try await deleteScheduleWithDescendants(schedule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reschedule a schedule to a new date and/or timeframe
    /// Only the parent's schedule moves - subtask schedules stay at their original dates
    /// Returns true if successful, false if section limit exceeded
    func rescheduleSchedule(_ schedule: Schedule, to newDate: Date, newTimeframe: Timeframe) async -> Bool {
        // Check section limits for Focus section at destination
        if schedule.section == .focus {
            let canAdd = canAddToFocusSection(timeframe: newTimeframe, date: newDate, excludingScheduleId: schedule.id)
            if !canAdd {
                errorMessage = "Focus section is full at destination (\(Section.focus.maxTasks(for: newTimeframe)!) max)"
                return false
            }
        }

        do {
            // Update schedule with new date and timeframe (subtask schedules stay)
            var updatedSchedule = schedule
            updatedSchedule.scheduleDate = newDate
            updatedSchedule.timeframe = newTimeframe

            try await scheduleRepository.updateSchedule(updatedSchedule)

            // Sync notification date to new schedule date
            await syncNotificationDate(taskId: schedule.taskId, newScheduleDate: newDate)

            // Refresh to update view
            await fetchSchedules()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// When a schedule date changes, move the notification to the same time on the new date
    func syncNotificationDate(taskId: UUID, newScheduleDate: Date) async {
        let calendar = Calendar.current
        guard let tasks = try? await taskRepository.fetchTasksByIds([taskId]),
              let task = tasks.first,
              task.notificationEnabled,
              let oldNotifDate = task.notificationDate else { return }

        let timeComponents = calendar.dateComponents([.hour, .minute], from: oldNotifDate)
        var newComponents = calendar.dateComponents([.year, .month, .day], from: newScheduleDate)
        newComponents.hour = timeComponents.hour
        newComponents.minute = timeComponents.minute

        guard let newNotifDate = calendar.date(from: newComponents) else { return }

        try? await taskRepository.updateTaskNotification(id: taskId, enabled: true, date: newNotifDate)
        NotificationService.shared.cancelNotification(taskId: taskId)
        NotificationService.shared.scheduleNotification(taskId: taskId, title: task.title, date: newNotifDate)
    }

    /// Check if Focus section has room at a specific date/timeframe
    /// Excludes a schedule ID to allow rescheduling within same section
    private func canAddToFocusSection(timeframe: Timeframe, date: Date, excludingScheduleId: UUID) -> Bool {
        // Count existing Focus schedules at destination (excluding the one being moved)
        let existingCount = schedules.filter {
            $0.section == .focus &&
            $0.timeframe == timeframe &&
            isSameTimeframe($0.scheduleDate, timeframe: timeframe, selectedDate: date) &&
            $0.id != excludingScheduleId
        }.count

        let maxAllowed = Section.focus.maxTasks(for: timeframe) ?? Int.max
        return existingCount < maxAllowed
    }

    /// Push schedule to next period (tomorrow, next week, next month, next year)
    /// Returns true if successful, false if section limit exceeded
    func pushScheduleToNext(_ schedule: Schedule) async -> Bool {
        let calendar = Calendar.current
        let newDate: Date?

        switch schedule.timeframe {
        case .daily:
            newDate = calendar.date(byAdding: .day, value: 1, to: schedule.scheduleDate)
        case .weekly:
            newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: schedule.scheduleDate)
        case .monthly:
            newDate = calendar.date(byAdding: .month, value: 1, to: schedule.scheduleDate)
        case .yearly:
            newDate = calendar.date(byAdding: .year, value: 1, to: schedule.scheduleDate)
        }

        guard let nextDate = newDate else { return false }
        return await rescheduleSchedule(schedule, to: nextDate, newTimeframe: schedule.timeframe)
    }

    /// Move a schedule to a different section (Focus <-> To-Do)
    /// Returns true if successful, false if section limit exceeded
    func moveScheduleToSection(_ schedule: Schedule, to targetSection: Section) async -> Bool {
        // Skip if already in target section
        guard schedule.section != targetSection else { return true }

        // Check section limits for Focus
        if targetSection == .focus {
            guard canAddTask(to: .focus, timeframe: schedule.timeframe, date: schedule.scheduleDate) else {
                errorMessage = "Focus section is full (\(Section.focus.maxTasks(for: schedule.timeframe)!) max)"
                return false
            }
        }

        // Update schedule
        var updatedSchedule = schedule
        updatedSchedule.section = targetSection

        do {
            try await scheduleRepository.updateSchedule(updatedSchedule)

            // Update local state
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index] = updatedSchedule
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Drag Reorder Methods

    /// Get schedules for a section filtered to current timeframe/date, by completion state
    private func schedulesForSection(_ section: Section, completed: Bool) -> [Schedule] {
        let filtered = schedules.filter { schedule in
            schedule.section == section &&
            isSameTimeframe(schedule.scheduleDate, timeframe: selectedTimeframe, selectedDate: selectedDate) &&
            (tasksMap[schedule.taskId]?.isCompleted ?? false) == completed
        }
        if completed { return filtered }

        var sorted = filtered.sorted { a, b in
            if a.isChildSchedule != b.isChildSchedule { return !a.isChildSchedule }
            return a.sortOrder < b.sortOrder
        }

        if section == .todo && todoPrioritySortEnabled {
            let ascending = todoPrioritySortDirection == .lowestFirst
            sorted.sort { a, b in
                let priorityA = tasksMap[a.taskId]?.priority.sortIndex ?? 2
                let priorityB = tasksMap[b.taskId]?.priority.sortIndex ?? 2
                if priorityA != priorityB {
                    return ascending ? priorityA > priorityB : priorityA < priorityB
                }
                return a.sortOrder < b.sortOrder
            }
        }

        return sorted
    }

    func uncompletedSchedulesForSection(_ section: Section) -> [Schedule] {
        schedulesForSection(section, completed: false)
    }

    func completedSchedulesForSection(_ section: Section) -> [Schedule] {
        schedulesForSection(section, completed: true)
    }

    // MARK: - Rollup Grouping

    /// Groups rollup schedules by their child-timeframe date bucket, sorted chronologically.
    /// Weekly parent → daily groups labelled "Monday, Feb 23"
    /// Monthly parent → weekly groups labelled "Week of Feb 16"
    /// Yearly parent → monthly groups labelled "February"
    var rollupSchedulesGrouped: [(date: Date, label: String, items: [Schedule])] {
        guard !rollupSchedules.isEmpty,
              let childTimeframe = selectedTimeframe.childTimeframe else { return [] }

        var calendar = Calendar.current
        calendar.firstWeekday = 1

        // Group schedules by their date bucket
        var groups: [Date: [Schedule]] = [:]
        for schedule in rollupSchedules {
            let bucketDate: Date
            switch childTimeframe {
            case .daily:
                bucketDate = calendar.startOfDay(for: schedule.scheduleDate)
            case .weekly:
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: schedule.scheduleDate)
                bucketDate = calendar.date(from: comps) ?? calendar.startOfDay(for: schedule.scheduleDate)
            case .monthly:
                let comps = calendar.dateComponents([.year, .month], from: schedule.scheduleDate)
                bucketDate = calendar.date(from: comps) ?? calendar.startOfDay(for: schedule.scheduleDate)
            case .yearly:
                bucketDate = calendar.startOfDay(for: schedule.scheduleDate)
            }
            groups[bucketDate, default: []].append(schedule)
        }

        return groups.keys.sorted().map { date in
            let items = groups[date]!.sorted { a, b in
                // Group child schedules (arrow indicator) together after standalone ones
                if a.isChildSchedule != b.isChildSchedule {
                    return !a.isChildSchedule
                }
                return a.sortOrder < b.sortOrder
            }
            return (date: date, label: rollupGroupLabel(date: date, childTimeframe: childTimeframe), items: items)
        }
    }

    private func rollupGroupLabel(date: Date, childTimeframe: Timeframe) -> String {
        switch childTimeframe {
        case .daily:
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: date)
        case .weekly:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "Week of \(f.string(from: date))"
        case .monthly:
            let f = DateFormatter()
            f.dateFormat = "MMMM"
            return f.string(from: date)
        case .yearly:
            let f = DateFormatter()
            f.dateFormat = "yyyy"
            return f.string(from: date)
        }
    }

    // MARK: - Flat Display Items

    var flattenedDisplayItems: [FocusFlatDisplayItem] {
        var result: [FocusFlatDisplayItem] = []

        let focusUncompleted = uncompletedSchedulesForSection(.focus)
        let focusCompleted = completedSchedulesForSection(.focus)
        let todoUncompleted = uncompletedSchedulesForSection(.todo)
        let todoCompleted = completedSchedulesForSection(.todo)

        // -- Focus section --
        result.append(.sectionHeader(.focus))

        if !isFocusSectionCollapsed {
            if focusUncompleted.isEmpty && focusCompleted.isEmpty {
                // Empty state: show inline add row instead of static text
                if canAddTask(to: .focus) {
                    result.append(.addFocusRow)
                } else {
                    result.append(.emptyState(.focus))
                }
            } else if focusUncompleted.isEmpty && !focusCompleted.isEmpty && !isFocusDoneCollapsing {
                result.append(.allDoneState)
            }

            for c in focusUncompleted {
                result.append(.schedule(c))
                if expandedTasks.contains(c.taskId) {
                    for subtask in getUncompletedSubtasks(for: c.taskId) {
                        result.append(.subtask(subtask, parentSchedule: c))
                    }
                    for subtask in getCompletedSubtasks(for: c.taskId) {
                        result.append(.subtask(subtask, parentSchedule: c))
                    }
                    result.append(.addSubtaskRow(parentId: c.taskId, parentSchedule: c))
                }
            }

            // (Add button is now on the Focus header pill — no inline add row when items exist)

            if isFocusDoneExpanded || !focusUncompleted.isEmpty || isFocusDoneCollapsing {
                for c in focusCompleted where !focusDoneHiddenIds.contains(c.id) {
                    result.append(.completedSchedule(c))
                }
            }

            // During collapse, use a FIXED spacer matching the post-collapse layout.
            // This prevents discrete jumps — To-Do section glides smoothly as items disappear.
            let minFocusRows = Section.focus.maxTasks(for: selectedTimeframe) ?? 3
            if isFocusDoneCollapsing {
                let focusRowCount = focusCompleted.count
                if focusRowCount > 0 && focusRowCount < minFocusRows {
                    let spacerHeight = CGFloat(minFocusRows - focusRowCount) * 48
                    result.append(.focusSpacer(spacerHeight))
                }
            } else {
                // When all tasks are completed, no spacer — To-Do sits right below
                // with the same natural margin whether 1 or 5 items are done.
                let allCompleted = focusUncompleted.isEmpty && !focusCompleted.isEmpty
                if !allCompleted {
                    // Ensure focus section has minimum height matching the max focus slots,
                    // plus a minimum drop-zone gap so cross-section drag always has room.
                    let focusRowCount = focusUncompleted.count + focusCompleted.count
                    if focusRowCount > 0 && focusRowCount < minFocusRows {
                        let spacerHeight = CGFloat(minFocusRows - focusRowCount) * 48
                        result.append(.focusSpacer(spacerHeight))
                    }
                }
            }
        }

        // -- To-Do section --
        result.append(.sectionHeader(.todo))

        if selectedTimeframe == .daily {
            // Daily: grouped by priority with collapsible headers
            let priorities: [Priority] = todoPrioritySortDirection == .highestFirst
                ? Priority.allCases
                : Priority.allCases.reversed()

            for priority in priorities {
                let schedulesForPriority = todoUncompleted.filter { c in
                    (tasksMap[c.taskId]?.priority ?? .low) == priority
                }

                result.append(.todoPriorityHeader(priority))

                if !collapsedTodoPriorities.contains(priority) {
                    for c in schedulesForPriority {
                        result.append(.schedule(c))
                        if expandedTasks.contains(c.taskId) {
                            for subtask in getUncompletedSubtasks(for: c.taskId) {
                                result.append(.subtask(subtask, parentSchedule: c))
                            }
                            for subtask in getCompletedSubtasks(for: c.taskId) {
                                result.append(.subtask(subtask, parentSchedule: c))
                            }
                            result.append(.addSubtaskRow(parentId: c.taskId, parentSchedule: c))
                        }
                    }
                    if schedulesForPriority.isEmpty {
                        result.append(.addTodoTaskRow(priority))
                    }
                }
            }
        } else {
            // Week/month/year: flat list without priority grouping
            if !isTodoSectionCollapsed {
                for c in todoUncompleted {
                    result.append(.schedule(c))
                    if expandedTasks.contains(c.taskId) {
                        for subtask in getUncompletedSubtasks(for: c.taskId) {
                            result.append(.subtask(subtask, parentSchedule: c))
                        }
                        for subtask in getCompletedSubtasks(for: c.taskId) {
                            result.append(.subtask(subtask, parentSchedule: c))
                        }
                        result.append(.addSubtaskRow(parentId: c.taskId, parentSchedule: c))
                    }
                }

                if !todoCompleted.isEmpty {
                    result.append(.donePill)
                }
            }
        }

        if selectedTimeframe == .daily && !todoCompleted.isEmpty {
            result.append(.donePill)
        }

        // -- Rollup section (child timeframe items within current period) --
        if !rollupSchedulesGrouped.isEmpty {
            result.append(.rollupSectionHeader)
            if !isRollupSectionCollapsed {
                for group in rollupSchedulesGrouped {
                    result.append(.rollupDayHeader(group.date, group.label))
                    if expandedRollupGroups.contains(group.date) {
                        for c in group.items {
                            result.append(.rollupSchedule(c))
                            if expandedTasks.contains(c.taskId) {
                                for subtask in getUncompletedSubtasks(for: c.taskId) {
                                    result.append(.subtask(subtask, parentSchedule: c))
                                }
                                for subtask in getCompletedSubtasks(for: c.taskId) {
                                    result.append(.subtask(subtask, parentSchedule: c))
                                }
                            }
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: - Section Config

    func sectionConfig(for section: Section) -> FocusSectionConfig {
        guard section == .focus else {
            return FocusSectionConfig(
                taskFont: .inter(.body),
                verticalPadding: 8,
                containerMinHeight: 0,
                completedTaskFont: .inter(.subheadline),
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        }

        // Fixed layout for focus section — scale container to max focus slots
        let maxSlots = Section.focus.maxTasks(for: selectedTimeframe) ?? 3
        let minHeight = CGFloat(maxSlots) * 48 + 86  // 48pt per row + header/padding
        return FocusSectionConfig(
            taskFont: .inter(.body),
            verticalPadding: 8,
            containerMinHeight: minHeight,
            completedTaskFont: .inter(.subheadline),
            completedVerticalPadding: 6,
            completedOpacity: 0.45
        )
    }

    // MARK: - Flat Move Handler

    /// Handle .onMove from the flat ForEach — supports schedule reorder, cross-section moves, and subtask reorder.
    /// Wrapped in a disabled-animation transaction to prevent stacking glitches from
    /// SwiftUI's optimistic .onMove animation conflicting with our data-driven reorder.
    func handleFlatMove(from source: IndexSet, to destination: Int) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            performFlatMove(from: source, to: destination)
        }
    }

    private func performFlatMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedDisplayItems
        guard let fromIdx = source.first else { return }

        // Check if it's a subtask move
        if case .subtask(let movedSubtask, let parentSchedule) = flat[fromIdx] {
            handleSubtaskMove(movedSubtask: movedSubtask, parentSchedule: parentSchedule, flat: flat, fromIdx: fromIdx, destination: destination)
            return
        }

        // Only .schedule items can be moved (besides subtasks handled above)
        guard case .schedule(let movedSchedule) = flat[fromIdx] else { return }

        let sourceSection = movedSchedule.section

        // Determine destination section by scanning backward for nearest section header or priority header.
        // Use destination - 1 so that inserting *before* a section header belongs to the previous section.
        var destSection: Section = .focus
        let sectionLookup = max(0, min(destination - 1, flat.count - 1))
        for i in stride(from: sectionLookup, through: 0, by: -1) {
            if case .sectionHeader(let section) = flat[i] {
                destSection = section
                break
            }
            // A todoPriorityHeader unambiguously means we're in the .todo section
            if case .todoPriorityHeader = flat[i] {
                destSection = .todo
                break
            }
        }

        if sourceSection == destSection {
            if destSection == .todo && todoPrioritySortEnabled {
                // -- Priority-aware reorder within to-do section --
                handleTodoPriorityMove(movedSchedule: movedSchedule, flat: flat, destination: destination)
            } else {
                // -- Same-section reorder (no priority awareness) --
                let sectionSchedules = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, schedule: Schedule)? in
                    if case .schedule(let c) = item, c.section == sourceSection {
                        return (i, c)
                    }
                    return nil
                }

                guard let scheduleFrom = sectionSchedules.firstIndex(where: { $0.schedule.id == movedSchedule.id }) else { return }

                var scheduleTo = sectionSchedules.count
                for (ci, entry) in sectionSchedules.enumerated() {
                    if destination <= entry.flatIdx {
                        scheduleTo = ci
                        break
                    }
                }
                if scheduleTo > scheduleFrom { scheduleTo = min(scheduleTo, sectionSchedules.count) }

                guard scheduleFrom != scheduleTo && scheduleFrom + 1 != scheduleTo else { return }

                var uncompleted = uncompletedSchedulesForSection(sourceSection)
                uncompleted.move(fromOffsets: IndexSet(integer: scheduleFrom), toOffset: scheduleTo)

                // Reassign sort orders on snapshot, then apply atomically
                var updatedSchedules = schedules
                var updates: [(id: UUID, sortOrder: Int)] = []
                for (index, c) in uncompleted.enumerated() {
                    if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                        updatedSchedules[mainIndex].sortOrder = index
                    }
                    updates.append((id: c.id, sortOrder: index))
                }
                schedules = updatedSchedules
                _Concurrency.Task { await persistScheduleSortOrders(updates) }
            }

        } else {
            // -- Cross-section move --
            if destSection == .focus {
                guard canAddTask(to: .focus, timeframe: movedSchedule.timeframe, date: movedSchedule.scheduleDate) else {
                    let max = Section.focus.maxTasks(for: movedSchedule.timeframe)!
                    // Force the list to rebuild so the optimistically-moved row
                    // snaps back to its original position immediately.
                    // Touching schedules triggers @Published and regenerates flattenedDisplayItems.
                    let snapshot = schedules
                    schedules = snapshot
                    errorMessage = "Focus section is full \(max)/\(max)"
                    return
                }
            }

            if destSection == .todo && todoPrioritySortEnabled {
                // -- Priority-aware cross-section move into To-Do --
                let destPriority = resolveDestinationTodoPriority(flat: flat, destination: destination)

                // Prepare task priority update (don't apply yet)
                var taskToUpdate: FocusTask? = nil
                if var task = tasksMap[movedSchedule.taskId], task.priority != destPriority {
                    task.priority = destPriority
                    task.modifiedDate = Date()
                    taskToUpdate = task
                }

                // Find insertion index within the destination priority group
                // (use current tasksMap for lookup since we haven't applied the priority change yet)
                let destPrioritySchedules = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, schedule: Schedule)? in
                    if case .schedule(let c) = item,
                       c.section == .todo,
                       (tasksMap[c.taskId]?.priority ?? .low) == destPriority {
                        return (i, c)
                    }
                    return nil
                }

                var priorityInsertIdx = destPrioritySchedules.count
                for (ci, entry) in destPrioritySchedules.enumerated() {
                    if destination <= entry.flatIdx {
                        priorityInsertIdx = ci
                        break
                    }
                }

                // Compute all changes on a snapshot, then apply atomically
                let sourceList = uncompletedSchedulesForSection(sourceSection)
                    .filter { $0.id != movedSchedule.id }
                var destPriorityList = uncompletedTodoSchedules(for: destPriority)
                let clampedIdx = min(priorityInsertIdx, destPriorityList.count)
                var movedC = movedSchedule
                movedC.section = .todo
                destPriorityList.insert(movedC, at: clampedIdx)

                // Build the new schedules array with all changes applied at once
                var updatedSchedules = schedules

                // Apply section change
                if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == movedSchedule.id }) {
                    updatedSchedules[mainIndex].section = .todo
                }

                // Reassign sort orders for source section
                var allUpdates: [(id: UUID, sortOrder: Int, section: Section)] = []
                for (index, c) in sourceList.enumerated() {
                    if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                        updatedSchedules[mainIndex].sortOrder = index
                    }
                    allUpdates.append((id: c.id, sortOrder: index, section: sourceSection))
                }

                // Reassign sort orders for destination priority group
                for (index, c) in destPriorityList.enumerated() {
                    if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                        updatedSchedules[mainIndex].sortOrder = index
                    }
                    allUpdates.append((id: c.id, sortOrder: index, section: .todo))
                }

                // Reassign sort orders for other todo priority groups (keep consistent)
                for priority in Priority.allCases where priority != destPriority {
                    let prioList = uncompletedTodoSchedules(for: priority)
                    for (index, c) in prioList.enumerated() {
                        if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                            updatedSchedules[mainIndex].sortOrder = index
                        }
                        allUpdates.append((id: c.id, sortOrder: index, section: .todo))
                    }
                }

                // Apply all state changes atomically (single @Published batch)
                if let task = taskToUpdate {
                    tasksMap[task.id] = task
                }
                schedules = updatedSchedules

                // Persist in background
                _Concurrency.Task { @MainActor in
                    if let task = taskToUpdate {
                        do { try await self.taskRepository.updateTask(task) }
                        catch { self.errorMessage = "Failed to update priority: \(error.localizedDescription)" }
                    }
                    await self.persistScheduleSortOrdersAndSections(allUpdates)
                }
            } else {
                // -- Standard cross-section move (no priority awareness needed) --
                let destSchedules = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, schedule: Schedule)? in
                    if case .schedule(let c) = item, c.section == destSection {
                        return (i, c)
                    }
                    return nil
                }

                var insertIdx = destSchedules.count
                for (ci, entry) in destSchedules.enumerated() {
                    if destination <= entry.flatIdx {
                        insertIdx = ci
                        break
                    }
                }

                moveScheduleToSectionAtIndex(movedSchedule, to: destSection, atIndex: insertIdx)
            }
        }
    }

    /// Determine which priority group contains the given destination index within the to-do section
    private func resolveDestinationTodoPriority(flat: [FocusFlatDisplayItem], destination: Int) -> Priority {
        let lookupIndex = max(0, min(destination - 1, flat.count - 1))
        for i in stride(from: lookupIndex, through: 0, by: -1) {
            if case .todoPriorityHeader(let priority) = flat[i] {
                return priority
            }
        }
        // No priority header found above destination — return the first priority in sort order
        let firstPriority: Priority = todoPrioritySortDirection == .highestFirst
            ? Priority.allCases.first! : Priority.allCases.last!
        return firstPriority
    }

    /// Handle drag-and-drop within the to-do section when priority sort is enabled
    private func handleTodoPriorityMove(movedSchedule: Schedule, flat: [FocusFlatDisplayItem], destination: Int) {
        let sourcePriority = tasksMap[movedSchedule.taskId]?.priority ?? .low
        let destinationPriority = resolveDestinationTodoPriority(flat: flat, destination: destination)

        if sourcePriority == destinationPriority {
            // Same-priority reorder
            let prioritySchedules = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, schedule: Schedule)? in
                if case .schedule(let c) = item,
                   c.section == .todo,
                   (tasksMap[c.taskId]?.priority ?? .low) == sourcePriority {
                    return (i, c)
                }
                return nil
            }

            guard let scheduleFrom = prioritySchedules.firstIndex(where: { $0.schedule.id == movedSchedule.id }) else { return }

            var scheduleTo = prioritySchedules.count
            for (ci, entry) in prioritySchedules.enumerated() {
                if destination <= entry.flatIdx {
                    scheduleTo = ci
                    break
                }
            }
            if scheduleTo > scheduleFrom { scheduleTo = min(scheduleTo, prioritySchedules.count) }
            guard scheduleFrom != scheduleTo && scheduleFrom + 1 != scheduleTo else { return }

            var samePriorityList = uncompletedTodoSchedules(for: sourcePriority)
            guard let fromIdx = samePriorityList.firstIndex(where: { $0.id == movedSchedule.id }) else { return }
            samePriorityList.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: min(scheduleTo, samePriorityList.count))

            var updatedSchedules = schedules
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, c) in samePriorityList.enumerated() {
                if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                    updatedSchedules[mainIndex].sortOrder = index
                }
                updates.append((id: c.id, sortOrder: index))
            }
            schedules = updatedSchedules
            _Concurrency.Task { await persistScheduleSortOrders(updates) }

        } else {
            // Cross-priority move: change the task's priority
            guard var task = tasksMap[movedSchedule.taskId] else { return }
            let oldPriority = task.priority
            task.priority = destinationPriority
            task.modifiedDate = Date()

            // Find insertion index in destination priority
            let destSchedules = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, schedule: Schedule)? in
                if case .schedule(let c) = item,
                   c.section == .todo,
                   (tasksMap[c.taskId]?.priority ?? .low) == destinationPriority,
                   c.id != movedSchedule.id {
                    return (i, c)
                }
                return nil
            }

            var insertIdx = destSchedules.count
            for (ci, entry) in destSchedules.enumerated() {
                if destination <= entry.flatIdx {
                    insertIdx = ci
                    break
                }
            }

            // Reassign sort orders in destination priority group
            var destList = uncompletedTodoSchedules(for: destinationPriority)
                .filter { $0.id != movedSchedule.id }
            let clampedIdx = min(insertIdx, destList.count)
            destList.insert(movedSchedule, at: clampedIdx)

            // Build updated schedules snapshot
            var updatedSchedules = schedules
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, c) in destList.enumerated() {
                if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                    updatedSchedules[mainIndex].sortOrder = index
                }
                updates.append((id: c.id, sortOrder: index))
            }

            // Reassign sort orders in source priority group
            let sourceList = uncompletedTodoSchedules(for: oldPriority)
            for (index, c) in sourceList.enumerated() {
                if let mainIndex = updatedSchedules.firstIndex(where: { $0.id == c.id }) {
                    updatedSchedules[mainIndex].sortOrder = index
                }
                updates.append((id: c.id, sortOrder: index))
            }

            // Apply all state changes atomically
            tasksMap[task.id] = task
            schedules = updatedSchedules

            // Persist priority change + sort orders
            _Concurrency.Task {
                do {
                    try await self.taskRepository.updateTask(task)
                } catch {
                    self.errorMessage = "Failed to update priority: \(error.localizedDescription)"
                }
                await self.persistScheduleSortOrders(updates)
            }
        }
    }

    /// Handle subtask reorder within the same parent
    private func handleSubtaskMove(movedSubtask: FocusTask, parentSchedule: Schedule, flat: [FocusFlatDisplayItem], fromIdx: Int, destination: Int) {
        let parentId = parentSchedule.taskId

        // Find parent schedule's flat index
        guard let parentFlatIdx = flat.firstIndex(where: {
            if case .schedule(let c) = $0 { return c.id == parentSchedule.id }
            return false
        }) else { return }

        // Find section bounds: next schedule/sectionHeader or end of array
        let sectionEnd = flat[(parentFlatIdx + 1)...].firstIndex(where: {
            if case .schedule = $0 { return true }
            if case .completedSchedule = $0 { return true }
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

    /// Move a schedule to a different section at a specific index
    func moveScheduleToSectionAtIndex(_ schedule: Schedule, to targetSection: Section, atIndex: Int) {
        guard schedule.section != targetSection else { return }

        // Validate Focus section capacity
        if targetSection == .focus {
            guard canAddTask(to: .focus, timeframe: schedule.timeframe, date: schedule.scheduleDate) else { return }
        }

        // Get source and target section lists
        var sourceList = uncompletedSchedulesForSection(schedule.section)
        var targetList = uncompletedSchedulesForSection(targetSection)

        // Remove from source
        sourceList.removeAll { $0.id == schedule.id }

        // Insert into target at the specified index (clamped)
        let insertIndex = min(atIndex, targetList.count)
        var movedSchedule = schedule
        movedSchedule.section = targetSection
        targetList.insert(movedSchedule, at: insertIndex)

        // Update in main schedules array
        if let mainIndex = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[mainIndex].section = targetSection
        }

        // Reassign sort orders for both sections
        for (index, c) in sourceList.enumerated() {
            if let mainIndex = schedules.firstIndex(where: { $0.id == c.id }) {
                schedules[mainIndex].sortOrder = index
            }
        }
        for (index, c) in targetList.enumerated() {
            if let mainIndex = schedules.firstIndex(where: { $0.id == c.id }) {
                schedules[mainIndex].sortOrder = index
            }
        }

        // Persist in background (include section so cross-section moves are saved)
        let allUpdates = sourceList.enumerated().map { (i, c) in (id: c.id, sortOrder: i, section: schedule.section) }
            + targetList.enumerated().map { (i, c) in (id: c.id, sortOrder: i, section: targetSection) }
        _Concurrency.Task { @MainActor in
            await persistScheduleSortOrdersAndSections(allUpdates)
        }
    }

    /// Persist schedule sort orders to database
    private func persistScheduleSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await scheduleRepository.updateScheduleSortOrders(updates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist schedule sort orders and sections to database
    private func persistScheduleSortOrdersAndSections(_ updates: [(id: UUID, sortOrder: Int, section: Section)]) async {
        do {
            try await scheduleRepository.updateScheduleSortOrdersAndSections(updates)
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

    /// Toggle section collapsed state
    func toggleSectionCollapsed(_ section: Section) {
        switch section {
        case .focus: isFocusSectionCollapsed.toggle()
        case .todo: isTodoSectionCollapsed.toggle()
        }
    }

    /// Check if section is collapsed
    func isSectionCollapsed(_ section: Section) -> Bool {
        switch section {
        case .focus: return isFocusSectionCollapsed
        case .todo: return isTodoSectionCollapsed
        }
    }

    // MARK: - To-Do Priority Sort

    func toggleTodoPrioritySort() {
        todoPrioritySortEnabled.toggle()
    }

    func toggleTodoPriorityCollapsed(_ priority: Priority) {
        if collapsedTodoPriorities.contains(priority) {
            collapsedTodoPriorities.remove(priority)
        } else {
            collapsedTodoPriorities.insert(priority)
        }
    }

    func isTodoPriorityCollapsed(_ priority: Priority) -> Bool {
        collapsedTodoPriorities.contains(priority)
    }

    /// Uncompleted to-do schedules for a given priority
    func uncompletedTodoSchedules(for priority: Priority) -> [Schedule] {
        uncompletedSchedulesForSection(.todo).filter { schedule in
            (tasksMap[schedule.taskId]?.priority ?? .low) == priority
        }
    }

    /// Update a task's priority and persist to Supabase
    func updateTaskPriority(_ task: FocusTask, priority: Priority) async {
        guard task.priority != priority else { return }

        var updatedTask = task
        updatedTask.priority = priority
        updatedTask.modifiedDate = Date()

        tasksMap[task.id] = updatedTask

        do {
            try await taskRepository.updateTask(updatedTask)
        } catch {
            errorMessage = "Failed to update priority: \(error.localizedDescription)"
            tasksMap[task.id] = task
        }
    }

    /// Title for the rollup/overview section based on the selected timeframe
    var overviewSectionTitle: String {
        switch selectedTimeframe {
        case .weekly: return "Assigned Tasks"
        case .monthly: return "Assigned Tasks"
        case .yearly: return "Assigned Tasks"
        default: return "Assigned Tasks"
        }
    }

    /// Toggle rollup section collapsed state
    func toggleRollupSection() {
        isRollupSectionCollapsed.toggle()
    }

    /// Toggle rollup group expanded/collapsed state
    func toggleRollupGroup(_ date: Date) {
        if expandedRollupGroups.contains(date) {
            expandedRollupGroups.remove(date)
        } else {
            expandedRollupGroups.insert(date)
        }
    }

    func isRollupGroupExpanded(_ date: Date) -> Bool {
        expandedRollupGroups.contains(date)
    }

    /// Toggle Done subsection collapsed state
    func toggleDoneSubsectionCollapsed() {
        isDoneSubsectionCollapsed.toggle()
    }

    /// Create a new task and immediately schedule it to the current timeframe/date/section
    @discardableResult
    func createTaskWithSchedule(title: String, section: Section, priority: Priority = .low) async -> (taskId: UUID, schedule: Schedule)? {
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
                isInLibrary: true,
                priority: priority
            )
            let createdTask = try await taskRepository.createTask(newTask)

            // Create schedule for current timeframe/date
            let maxSort = schedules
                .filter { $0.section == section &&
                    isSameTimeframe($0.scheduleDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let schedule = Schedule(
                userId: userId,
                taskId: createdTask.id,
                timeframe: selectedTimeframe,
                section: section,
                scheduleDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdSchedule = try await scheduleRepository.createSchedule(schedule)

            // Update local state
            tasksMap[createdTask.id] = createdTask
            schedules.append(createdSchedule)

            return (taskId: createdTask.id, schedule: createdSchedule)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Create task + schedule + subtasks atomically, updating view state once at the end
    func createTaskWithSubtasks(title: String, section: Section, subtaskTitles: [String], priority: Priority = .low, categoryId: UUID? = nil) async {
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
                isInLibrary: true,
                priority: priority,
                categoryId: categoryId
            )
            let createdTask = try await taskRepository.createTask(newTask)

            // 2. Create schedule
            let maxSort = schedules
                .filter { $0.section == section &&
                    isSameTimeframe($0.scheduleDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let schedule = Schedule(
                userId: userId,
                taskId: createdTask.id,
                timeframe: selectedTimeframe,
                section: section,
                scheduleDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdSchedule = try await scheduleRepository.createSchedule(schedule)

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
                schedules.append(createdSchedule)
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

    /// Create a list + items and immediately schedule to the current timeframe/date/section
    func createListWithSchedule(title: String, section: Section, itemTitles: [String], priority: Priority = .low, categoryId: UUID? = nil) async {
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
            // 1. Create the list
            let newList = FocusTask(
                userId: userId,
                title: title,
                type: .list,
                isCompleted: false,
                isInLibrary: true,
                priority: priority,
                categoryId: categoryId
            )
            let createdList = try await taskRepository.createTask(newList)

            // 2. Create items as subtasks
            var createdItems: [FocusTask] = []
            for itemTitle in itemTitles where !itemTitle.isEmpty {
                let item = try await taskRepository.createSubtask(
                    title: itemTitle,
                    parentTaskId: createdList.id,
                    userId: userId
                )
                createdItems.append(item)
            }

            // 3. Create schedule
            let maxSort = schedules
                .filter { $0.section == section &&
                    isSameTimeframe($0.scheduleDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let schedule = Schedule(
                userId: userId,
                taskId: createdList.id,
                timeframe: selectedTimeframe,
                section: section,
                scheduleDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdSchedule = try await scheduleRepository.createSchedule(schedule)

            // 4. Batch view update
            withAnimation(.easeInOut(duration: 0.3)) {
                tasksMap[createdList.id] = createdList
                schedules.append(createdSchedule)
                if !createdItems.isEmpty {
                    subtasksMap[createdList.id] = createdItems
                    for item in createdItems {
                        tasksMap[item.id] = item
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a project + tasks + subtasks and immediately schedule to the current timeframe/date/section
    func createProjectWithSchedule(title: String, section: Section, draftTasks: [DraftTask], priority: Priority = .low, categoryId: UUID? = nil) async {
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
            // 1. Create the project
            let newProject = FocusTask(
                userId: userId,
                title: title,
                type: .project,
                isCompleted: false,
                isInLibrary: true,
                priority: priority,
                categoryId: categoryId
            )
            let createdProject = try await taskRepository.createTask(newProject)

            // 2. Create tasks under the project
            for (index, draft) in draftTasks.enumerated() {
                let taskTitle = draft.title.trimmingCharacters(in: .whitespaces)
                guard !taskTitle.isEmpty else { continue }

                let projectTask = try await taskRepository.createProjectTask(
                    title: taskTitle,
                    projectId: createdProject.id,
                    userId: userId,
                    sortOrder: index
                )

                // Create subtasks for each task
                for subtaskDraft in draft.subtasks {
                    let subtaskTitle = subtaskDraft.title.trimmingCharacters(in: .whitespaces)
                    guard !subtaskTitle.isEmpty else { continue }
                    _ = try await taskRepository.createSubtask(
                        title: subtaskTitle,
                        parentTaskId: projectTask.id,
                        userId: userId,
                        projectId: createdProject.id
                    )
                }
            }

            // 3. Create schedule
            let maxSort = schedules
                .filter { $0.section == section &&
                    isSameTimeframe($0.scheduleDate, timeframe: selectedTimeframe, selectedDate: selectedDate) }
                .map { $0.sortOrder }
                .max() ?? -1
            let schedule = Schedule(
                userId: userId,
                taskId: createdProject.id,
                timeframe: selectedTimeframe,
                section: section,
                scheduleDate: selectedDate,
                sortOrder: maxSort + 1
            )
            let createdSchedule = try await scheduleRepository.createSchedule(schedule)

            // 4. Batch view update
            withAnimation(.easeInOut(duration: 0.3)) {
                tasksMap[createdProject.id] = createdProject
                schedules.append(createdSchedule)
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
                    uncompletedSchedulesForSection(.focus).allSatisfy { $0.taskId == task.id }

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
        let completed = completedSchedulesForSection(.focus)
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
        for (index, schedule) in reversed.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay + Double(index) * 0.3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    _ = self.focusDoneHiddenIds.insert(schedule.id)
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
                        let willTriggerCollapse = uncompletedSchedulesForSection(.focus)
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

        // Get parent's schedule at the current timeframe
        let parentSchedule = schedules.first {
            $0.taskId == parentId && $0.timeframe == selectedTimeframe
        }

        // Filter subtasks that count toward auto-completion:
        // 1. Subtasks with NO schedule (followers), OR
        // 2. Subtasks with schedule at SAME timeframe as parent
        let relevantSubtasks = subtasks.filter { subtask in
            let subtaskSchedule = schedules.first { $0.taskId == subtask.id }

            if subtaskSchedule == nil {
                return true  // Follower subtask - counts toward parent completion
            }

            // Only count if same timeframe as parent
            return subtaskSchedule?.timeframe == parentSchedule?.timeframe
        }

        // If no relevant subtasks, don't auto-complete
        guard !relevantSubtasks.isEmpty else { return false }

        // Auto-complete if all relevant subtasks are complete
        return relevantSubtasks.allSatisfy { $0.isCompleted }
    }

    // MARK: - Schedule Methods (Trickle-Down)

    /// Fetch child schedules for all current schedules recursively
    func fetchChildSchedules() async {
        for schedule in schedules where schedule.canBreakdown {
            await fetchChildrenRecursively(for: schedule)
        }
    }

    /// Recursively fetch children and grandchildren
    private func fetchChildrenRecursively(for schedule: Schedule) async {
        do {
            let children = try await scheduleRepository.fetchChildSchedules(
                parentId: schedule.id
            )
            childSchedulesMap[schedule.id] = children

            // Recursively fetch grandchildren for children that can break down
            for child in children where child.canBreakdown {
                await fetchChildrenRecursively(for: child)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Get child schedules for a parent
    func getChildSchedules(for parentId: UUID) -> [Schedule] {
        childSchedulesMap[parentId] ?? []
    }

    /// Get child count for a schedule
    func childCount(for scheduleId: UUID) -> Int {
        childSchedulesMap[scheduleId]?.count ?? 0
    }

    /// Schedule a task to a specific date and timeframe
    func scheduleToTimeframe(_ schedule: Schedule, toDate date: Date, targetTimeframe: Timeframe) async {
        do {
            let child = try await scheduleRepository.createChildSchedule(
                parentSchedule: schedule,
                childDate: date,
                targetTimeframe: targetTimeframe
            )

            // Update local state
            if var children = childSchedulesMap[schedule.id] {
                children.append(child)
                childSchedulesMap[schedule.id] = children
            } else {
                childSchedulesMap[schedule.id] = [child]
            }

            // Add to schedules list so it appears when viewing child timeframe
            schedules.append(child)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Assign a schedule to a specific day (reschedules from weekly/monthly/yearly to daily)
    func assignToDay(_ schedule: Schedule, date: Date) async {
        _ = await rescheduleSchedule(schedule, to: date, newTimeframe: .daily)
    }

    /// Schedule a subtask to a target timeframe (creates schedule for subtask that doesn't have one)
    func scheduleSubtask(_ subtask: FocusTask, parentSchedule: Schedule, toDate: Date, targetTimeframe: Timeframe) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        do {
            // Create schedule for the subtask at target timeframe
            let subtaskSchedule = Schedule(
                userId: userId,
                taskId: subtask.id,
                timeframe: targetTimeframe,
                section: parentSchedule.section,
                scheduleDate: toDate,
                sortOrder: 0,
                parentScheduleId: parentSchedule.id
            )
            let created = try await scheduleRepository.createSchedule(subtaskSchedule)

            // Update local state
            schedules.append(created)
            tasksMap[subtask.id] = subtask

            // Track as child of parent schedule
            if var children = childSchedulesMap[parentSchedule.id] {
                children.append(created)
                childSchedulesMap[parentSchedule.id] = children
            } else {
                childSchedulesMap[parentSchedule.id] = [created]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Calculate available slots for scheduling to any target timeframe
    func availableSlotsForSchedule(_ schedule: Schedule, targetTimeframe: Timeframe) -> [Date] {
        guard schedule.timeframe.availableBreakdownTimeframes.contains(targetTimeframe) else {
            return []
        }

        let calendar = Calendar.current
        var slots: [Date] = []

        // Generate slots based on target timeframe within the schedule's date range
        switch targetTimeframe {
        case .monthly:
            // Generate all 12 months of the schedule's year
            let year = calendar.component(.year, from: schedule.scheduleDate)
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
            switch schedule.timeframe {
            case .yearly:
                // All weeks in the year
                let year = calendar.component(.year, from: schedule.scheduleDate)
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
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: schedule.scheduleDate)),
                      let monthRange = calendar.range(of: .day, in: .month, for: schedule.scheduleDate) else {
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
            switch schedule.timeframe {
            case .yearly:
                // All days in the year (too many - use calendar picker navigation instead)
                // Return empty and let the calendar picker handle display
                return []

            case .monthly:
                // All days in the month
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: schedule.scheduleDate)),
                      let monthRange = calendar.range(of: .day, in: .month, for: schedule.scheduleDate) else {
                    return []
                }

                for day in monthRange {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        slots.append(date)
                    }
                }

            case .weekly:
                // All 7 days of the week
                guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: schedule.scheduleDate)) else {
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
        let existingChildren = getChildSchedules(for: schedule.id)
            .filter { $0.timeframe == targetTimeframe }
        let existingDates = Set(existingChildren.map { calendar.startOfDay(for: $0.scheduleDate) })

        return slots.filter { !existingDates.contains(calendar.startOfDay(for: $0)) }
    }

}
