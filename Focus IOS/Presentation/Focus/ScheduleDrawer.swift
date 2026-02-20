//
//  ScheduleDrawer.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Filter Type

enum ScheduleFilter: Equatable {
    case today
    case all
    case category(UUID)
}

// MARK: - Schedule Drawer

struct ScheduleDrawer: View {
    @ObservedObject var viewModel: FocusTabViewModel
    @ObservedObject var timelineVM: TimelineViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @State private var selectedFilter: ScheduleFilter = .today
    @State private var categories: [Category] = []

    // Log task state (for All / Category filters)
    @State private var logTasks: [FocusTask] = []
    @State private var logSubtasksMap: [UUID: [FocusTask]] = [:]
    @State private var logExpandedTasks: Set<UUID> = []

    private let categoryRepository = CategoryRepository()
    private let taskRepository = TaskRepository()

    // MARK: - Computed Properties

    @ViewBuilder
    private var titleView: some View {
        switch selectedFilter {
        case .today:
            let formatted: String = {
                let f = DateFormatter()
                f.locale = LanguageManager.shared.locale
                f.dateFormat = "MMM d"
                return f.string(from: viewModel.selectedDate)
            }()
            (Text(LocalizedStringKey("Today")) + Text(", \(formatted)"))
        case .all:
            Text(LocalizedStringKey("All Tasks"))
        case .category(let id):
            if let name = categories.first(where: { $0.id == id })?.name {
                Text(name)
            } else {
                Text(LocalizedStringKey("Category"))
            }
        }
    }

    private var scheduledTaskIds: Set<UUID> {
        Set(timelineVM.timedCommitments.map { $0.taskId })
    }

    private var filteredLogTasks: [FocusTask] {
        var filtered = logTasks.filter { !$0.isCompleted && !scheduledTaskIds.contains($0.id) }

        if case .category(let categoryId) = selectedFilter {
            filtered = filtered.filter { $0.categoryId == categoryId }
        }

        return filtered.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var dailyCommitments: [Commitment] {
        viewModel.commitments.filter { commitment in
            commitment.timeframe == .daily &&
            commitment.scheduledTime == nil &&
            !scheduledTaskIds.contains(commitment.taskId) &&
            viewModel.isSameTimeframe(
                commitment.commitmentDate,
                timeframe: .daily,
                selectedDate: viewModel.selectedDate
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag handle indicator
            HStack {
                Spacer()
                Capsule()
                    .fill(Color(.systemGray3))
                    .frame(width: 36, height: 5)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Title
            titleView
                .font(.sf(.title2, weight: .bold))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Add a task row
            Button {
                viewModel.addTaskSection = .extra
                viewModel.showAddTaskSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.sf(.body))
                        .foregroundColor(.secondary)

                    Text("Add a task")
                        .font(.sf(.body))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 12)

            // Task list
            ScrollView {
                VStack(spacing: 8) {
                    if selectedFilter == .today {
                        todayTasksList
                    } else {
                        logTasksList
                    }
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 0)

            // Bottom filter pills
            filterPills
                .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 12, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            await fetchCategories()
            await fetchLogTasks()
        }
    }

    // MARK: - Today Tasks List

    @ViewBuilder
    private var todayTasksList: some View {
        ForEach(dailyCommitments) { commitment in
            if let task = viewModel.tasksMap[commitment.taskId] {
                let subtasks = viewModel.getSubtasks(for: task.id)
                let hasSubtasks = !subtasks.isEmpty
                let isExpanded = viewModel.isExpanded(task.id)

                VStack(spacing: 0) {
                    // Main task row
                    HStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            _Concurrency.Task { @MainActor in
                                await viewModel.toggleTaskCompletion(task)
                            }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.sf(.title3))
                                .foregroundColor(task.isCompleted ? Color(red: 0x61/255.0, green: 0x10/255.0, blue: 0xF8/255.0).opacity(0.6) : .gray)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.sf(.body))
                                .strikethrough(task.isCompleted)
                                .foregroundColor(task.isCompleted ? .secondary : .primary)

                            if hasSubtasks {
                                let completedCount = subtasks.filter { $0.isCompleted }.count
                                Text("\(completedCount)/\(subtasks.count) subtasks")
                                    .font(.sf(.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleExpanded(task.id)
                            }
                        }
                        .onLongPressGesture {
                            viewModel.selectedTaskForDetails = task
                        }

                        DragHandleView()
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                    .onChanged { value in
                                        let subtaskLabel: String? = hasSubtasks
                                            ? "\(subtasks.filter { $0.isCompleted }.count)/\(subtasks.count) subtasks"
                                            : nil
                                        timelineVM.handleScheduleDragChanged(
                                            location: value.location,
                                            taskId: task.id,
                                            commitmentId: commitment.id,
                                            taskTitle: task.title,
                                            isCompleted: task.isCompleted,
                                            subtaskText: subtaskLabel
                                        )
                                    }
                                    .onEnded { value in
                                        timelineVM.handleScheduleDragEnded(location: value.location)
                                    }
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .opacity(timelineVM.scheduleDragInfo?.taskId == task.id ? 0.4 : 1.0)

                    // Subtasks (shown when expanded)
                    if isExpanded {
                        VStack(spacing: 0) {
                            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                                FocusSubtaskRow(
                                    subtask: subtask,
                                    parentId: task.id,
                                    parentCommitment: commitment,
                                    viewModel: viewModel
                                )

                                if index < subtasks.count - 1 {
                                    Divider()
                                }
                            }
                            Divider()
                            FocusInlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                        }
                        .padding(.leading, 32)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    // MARK: - Log Tasks List

    @ViewBuilder
    private var logTasksList: some View {
        if filteredLogTasks.isEmpty {
            Text("No tasks")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            ForEach(filteredLogTasks) { task in
                let subtasks = getLogSubtasks(for: task.id)
                let hasSubtasks = !subtasks.isEmpty
                let isExpanded = logExpandedTasks.contains(task.id)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            _Concurrency.Task { @MainActor in
                                await toggleLogTaskCompletion(task)
                            }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.sf(.title3))
                                .foregroundColor(task.isCompleted ? Color(red: 0x61/255.0, green: 0x10/255.0, blue: 0xF8/255.0).opacity(0.6) : .gray)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.sf(.body))
                                .strikethrough(task.isCompleted)
                                .foregroundColor(task.isCompleted ? .secondary : .primary)

                            if hasSubtasks {
                                let completedCount = subtasks.filter { $0.isCompleted }.count
                                Text("\(completedCount)/\(subtasks.count) subtasks")
                                    .font(.sf(.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                toggleLogExpanded(task.id)
                            }
                        }

                        DragHandleView()
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                    .onChanged { value in
                                        let subtaskLabel: String? = hasSubtasks
                                            ? "\(subtasks.filter { $0.isCompleted }.count)/\(subtasks.count) subtasks"
                                            : nil
                                        timelineVM.handleScheduleDragChanged(
                                            location: value.location,
                                            taskId: task.id,
                                            commitmentId: nil,
                                            taskTitle: task.title,
                                            isCompleted: task.isCompleted,
                                            subtaskText: subtaskLabel
                                        )
                                    }
                                    .onEnded { value in
                                        timelineVM.handleScheduleDragEnded(location: value.location)
                                    }
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .opacity(timelineVM.scheduleDragInfo?.taskId == task.id ? 0.4 : 1.0)

                    if isExpanded {
                        VStack(spacing: 0) {
                            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                                logSubtaskRow(subtask: subtask, parentId: task.id)

                                if index < subtasks.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.leading, 32)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    @ViewBuilder
    private func logSubtaskRow(subtask: FocusTask, parentId: UUID) -> some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.sf(.subheadline))
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task { @MainActor in
                    await toggleLogSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.subheadline))
                    .foregroundColor(subtask.isCompleted ? Color(red: 0x61/255.0, green: 0x10/255.0, blue: 0xF8/255.0).opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Log Task Helpers

    private func getLogSubtasks(for taskId: UUID) -> [FocusTask] {
        let subtasks = logSubtasksMap[taskId] ?? []
        return subtasks.sorted { !$0.isCompleted && $1.isCompleted }
    }

    private func toggleLogExpanded(_ taskId: UUID) {
        if logExpandedTasks.contains(taskId) {
            logExpandedTasks.remove(taskId)
        } else {
            logExpandedTasks.insert(taskId)
        }
    }

    private func toggleLogTaskCompletion(_ task: FocusTask) async {
        do {
            if task.isCompleted {
                try await taskRepository.uncompleteTask(id: task.id)
            } else {
                try await taskRepository.completeTask(id: task.id)
            }

            if let index = logTasks.firstIndex(where: { $0.id == task.id }) {
                logTasks[index].isCompleted.toggle()
                logTasks[index].completedDate = logTasks[index].isCompleted ? Date() : nil
            }

            NotificationCenter.default.post(
                name: .taskCompletionChanged,
                object: nil,
                userInfo: [
                    TaskNotificationKeys.taskId: task.id,
                    TaskNotificationKeys.isCompleted: !task.isCompleted,
                    TaskNotificationKeys.completedDate: (task.isCompleted ? nil : Date()) as Any,
                    TaskNotificationKeys.source: TaskNotificationSource.log.rawValue
                ]
            )
        } catch {
            // Silent fail
        }
    }

    private func toggleLogSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        do {
            if subtask.isCompleted {
                try await taskRepository.uncompleteTask(id: subtask.id)
            } else {
                try await taskRepository.completeTask(id: subtask.id)
            }

            if var subtasks = logSubtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                subtasks[index].isCompleted.toggle()
                subtasks[index].completedDate = subtasks[index].isCompleted ? Date() : nil
                logSubtasksMap[parentId] = subtasks
            }

            NotificationCenter.default.post(
                name: .taskCompletionChanged,
                object: nil,
                userInfo: [
                    TaskNotificationKeys.taskId: subtask.id,
                    TaskNotificationKeys.isCompleted: !subtask.isCompleted,
                    TaskNotificationKeys.completedDate: (subtask.isCompleted ? nil : Date()) as Any,
                    TaskNotificationKeys.source: TaskNotificationSource.log.rawValue
                ]
            )
        } catch {
            // Silent fail
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(title: "Today", isSelected: selectedFilter == .today) {
                    selectedFilter = .today
                }

                FilterPill(title: "All", isSelected: selectedFilter == .all) {
                    selectedFilter = .all
                }

                ForEach(categories) { category in
                    FilterPill(
                        title: category.name,
                        isSelected: selectedFilter == .category(category.id)
                    ) {
                        selectedFilter = .category(category.id)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data

    private func fetchCategories() async {
        do {
            categories = try await categoryRepository.fetchCategories(type: .task)
        } catch {
            // Silent fail — pills just won't show categories
        }
    }

    private func fetchLogTasks() async {
        do {
            let allTasks = try await taskRepository.fetchTasks(ofType: .task)
            logTasks = allTasks.filter { $0.parentTaskId == nil }

            var newSubtasksMap: [UUID: [FocusTask]] = [:]
            for task in allTasks where task.parentTaskId != nil {
                newSubtasksMap[task.parentTaskId!, default: []].append(task)
            }
            logSubtasksMap = newSubtasksMap
        } catch {
            // Silent fail
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.sf(.subheadline, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}
