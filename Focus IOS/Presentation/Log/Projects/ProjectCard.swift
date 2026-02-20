//
//  ProjectCard.swift
//  Focus IOS
//

import SwiftUI
import Auth

// MARK: - Project Card

struct ProjectCard: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    @State private var isInlineAddFocused = false

    private var taskProgress: (completed: Int, total: Int) {
        viewModel.taskProgress(for: project.id)
    }

    private var subtaskProgress: (completed: Int, total: Int) {
        viewModel.subtaskProgress(for: project.id)
    }

    private var progressPercentage: Double {
        viewModel.progressPercentage(for: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            projectHeader

            // Progress bar
            if !project.isCompleted && taskProgress.total > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 3)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progressPercentage, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal)
                .padding(.bottom, viewModel.isExpanded(project.id) ? 0 : 12)
            }

            // Expanded content
            if viewModel.isExpanded(project.id) {
                expandedContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Header

    private var projectHeader: some View {
        HStack(spacing: 12) {
            // Project icon
            ProjectIconShape()
                .frame(width: 64, height: 64)
                .padding(.leading, -18)
                .padding(.trailing, -12)
                .padding(.vertical, -16)
                .opacity(project.isCompleted ? 0.4 : 1.0)

            // Title and progress
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.montserrat(.title3))
                    .lineLimit(1)
                    .strikethrough(project.isCompleted)
                    .foregroundColor(project.isCompleted ? .secondary : .primary)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Task")
                            .font(.montserrat(.caption))
                        Text("\(taskProgress.completed)/\(taskProgress.total)")
                            .font(.montserrat(.caption))
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text("Sub Task")
                            .font(.montserrat(.caption))
                        Text("\(subtaskProgress.completed)/\(subtaskProgress.total)")
                            .font(.montserrat(.caption))
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if project.isCompleted {
                // Blue checkmark for completed projects
                Image(systemName: "checkmark.circle.fill")
                    .font(.montserrat(.title3))
                    .foregroundColor(.blue)
            } else if !viewModel.isEditMode, let onDragChanged, let onDragEnded {
                // Drag handle
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("projectList"))
                            .onChanged { value in onDragChanged(value) }
                            .onEnded { _ in onDragEnded() }
                    )
            } else {
                DragHandleView()
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            _Concurrency.Task { @MainActor in
                await viewModel.toggleExpanded(project.id)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.selectedProjectForDetails = project
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal)

            if viewModel.isLoadingProjectTasks.contains(project.id) {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding()
            } else {
                let items = viewModel.flattenedProjectItems(for: project.id)

                if items.count <= 1 {
                    // Only the addTaskRow — no tasks yet
                    Text("No tasks yet")
                        .font(.montserrat(.subheadline))
                        .foregroundColor(.secondary)
                        .padding()

                    InlineAddProjectTaskRow(
                        projectId: project.id,
                        viewModel: viewModel,
                        isAnyAddFieldActive: $isInlineAddFocused
                    )
                    .padding(.horizontal, 16)
                } else {
                    List {
                        ForEach(items) { item in
                            switch item {
                            case .task(let task):
                                Group {
                                    if task.parentTaskId != nil {
                                        ProjectSubtaskRow(
                                            subtask: task,
                                            parentId: task.parentTaskId!,
                                            viewModel: viewModel
                                        )
                                        .padding(.leading, 32)
                                    } else {
                                        ProjectTaskRow(
                                            task: task,
                                            projectId: project.id,
                                            viewModel: viewModel
                                        )
                                    }
                                }
                                .moveDisabled(task.isCompleted || viewModel.isEditMode)
                                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.visible)

                            case .addSubtaskRow(let parentId):
                                InlineAddSubtaskForProjectRow(
                                    parentId: parentId,
                                    viewModel: viewModel,
                                    isAnyAddFieldActive: $isInlineAddFocused
                                )
                                .padding(.leading, 32)
                                .moveDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .addTaskRow:
                                InlineAddProjectTaskRow(
                                    projectId: project.id,
                                    viewModel: viewModel,
                                    isAnyAddFieldActive: $isInlineAddFocused
                                )
                                .moveDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .onMove { from, to in
                            viewModel.handleProjectContentFlatMove(from: from, to: to, projectId: project.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .keyboardDismissOverlay(isActive: $isInlineAddFocused)
                    .frame(minHeight: items.reduce(CGFloat(0)) { sum, item in
                        if case .task(let t) = item, t.parentTaskId == nil { return sum + 70 }
                        return sum + 44
                    })
                }
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Project Task Row

struct ProjectTaskRow: View {
    let task: FocusTask
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var showDeleteConfirmation = false

    private var subtaskCount: (completed: Int, total: Int) {
        let subtasks = viewModel.subtasksMap[task.id] ?? []
        let completed = subtasks.filter { $0.isCompleted }.count
        return (completed, subtasks.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Task title + subtask count
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.montserrat(.body))
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                if subtaskCount.total > 0 {
                    Text("\(subtaskCount.completed)/\(subtaskCount.total) subtasks")
                        .font(.montserrat(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Completion button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task {
                    await viewModel.toggleTaskCompletion(task, projectId: projectId)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.montserrat(.title3))
                    .foregroundColor(task.isCompleted ? .blue : .gray)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            _Concurrency.Task {
                await viewModel.toggleTaskExpanded(task.id)
            }
        }
        .contextMenu {
            if !task.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = task
                }

                Divider()

                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteProjectTask(task, projectId: projectId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(task.title)\"?")
        }
    }
}

// MARK: - Project Subtask Row

struct ProjectSubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.montserrat(.subheadline))
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.montserrat(.subheadline))
                    .foregroundColor(subtask.isCompleted ? .blue : .gray)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedTaskForDetails = subtask
        }
        .contextMenu {
            if !subtask.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = subtask
                }

                Divider()

                ContextMenuItems.deleteButton {
                    _Concurrency.Task {
                        await viewModel.deleteSubtask(subtask, parentId: parentId)
                    }
                }
            }
        }
    }
}

// MARK: - Inline Add Project Task Row

struct InlineAddProjectTaskRow: View {
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @Binding var isAnyAddFieldActive: Bool
    @State private var newTaskTitle = ""
    @State private var isEditing = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Task title", text: $newTaskTitle)
                    .font(.montserrat(.subheadline))
                    .focused($isFocused)
                    .onSubmit {
                        submitTask()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.montserrat(.subheadline))
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.montserrat(.subheadline))
                        Text("Add task")
                            .font(.montserrat(.subheadline))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 8)
        .onChange(of: isFocused) { _, focused in
            if focused {
                isAnyAddFieldActive = true
            } else if !isSubmitting {
                isAnyAddFieldActive = false
                isEditing = false
                newTaskTitle = ""
            }
        }
    }

    private func submitTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        isSubmitting = true
        _Concurrency.Task {
            await viewModel.createProjectTask(title: title, projectId: projectId)
            newTaskTitle = ""
            isFocused = true
            isSubmitting = false
        }
    }
}

// MARK: - Inline Add Subtask For Project Row

struct InlineAddSubtaskForProjectRow: View {
    let parentId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @Binding var isAnyAddFieldActive: Bool
    @State private var newTitle = ""
    @State private var isEditing = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Subtask title", text: $newTitle)
                    .font(.montserrat(.subheadline))
                    .focused($isFocused)
                    .onSubmit {
                        submitSubtask()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.montserrat(.caption))
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.montserrat(.subheadline))
                        Text("Add subtask")
                            .font(.montserrat(.subheadline))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .onChange(of: isFocused) { _, focused in
            if focused {
                isAnyAddFieldActive = true
            } else if !isSubmitting {
                isAnyAddFieldActive = false
                isEditing = false
                newTitle = ""
            }
        }
    }

    private func submitSubtask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        isSubmitting = true
        _Concurrency.Task {
            await viewModel.createSubtask(title: title, parentId: parentId)
            newTitle = ""
            isFocused = true
            isSubmitting = false
        }
    }
}

// MARK: - Project Icon Shape

struct ProjectIconShape: View {
    var body: some View {
        Image("ProjectIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
