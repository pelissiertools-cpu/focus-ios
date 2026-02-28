//
//  ProjectCard.swift
//  Focus IOS
//

import SwiftUI

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
                            .fill(Color.appRed)
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
            // Edit mode: selection circle
            if viewModel.isEditMode && !project.isCompleted {
                Image(systemName: viewModel.selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedProjectIds.contains(project.id) ? .appRed : .secondary)
            }

            // Project icon
            ProjectIconShape()
                .frame(width: 32, height: 32)
                .foregroundColor(.orange)
                .opacity(project.isCompleted ? 0.4 : 1.0)

            // Title and progress
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.inter(.title3, weight: .bold))
                    .lineLimit(1)
                    .strikethrough(project.isCompleted)
                    .foregroundColor(project.isCompleted ? .secondary : .primary)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Task")
                            .font(.inter(.caption))
                        Text("\(taskProgress.completed)/\(taskProgress.total)")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text("Sub Task")
                            .font(.inter(.caption))
                        Text("\(subtaskProgress.completed)/\(subtaskProgress.total)")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if project.isCompleted {
                // Checkmark for completed projects (matches Focus tab all-done icon)
                Image("CheckCircle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(Color.completedPurple)
            } else if !viewModel.isEditMode, let onDragChanged, let onDragEnded {
                // Drag handle
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("projectList"))
                            .onChanged { value in onDragChanged(value) }
                            .onEnded { _ in onDragEnded() }
                    )
            } else if !viewModel.isEditMode {
                DragHandleView()
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isEditMode && !project.isCompleted {
                viewModel.toggleProjectSelection(project.id)
            } else if !viewModel.isEditMode {
                _Concurrency.Task { @MainActor in
                    await viewModel.toggleExpanded(project.id)
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !viewModel.isEditMode {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.selectedProjectForDetails = project
            }
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
                        .font(.inter(.headline))
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    InlineAddRow(
                        placeholder: "Task title",
                        buttonLabel: "Add task",
                        onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 8
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
                                InlineAddRow(
                                    placeholder: "Subtask title",
                                    buttonLabel: "Add subtask",
                                    onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                                    isAnyAddFieldActive: $isInlineAddFocused,
                                    iconFont: .inter(.caption),
                                    verticalPadding: 6
                                )
                                .padding(.leading, 32)
                                .moveDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .addTaskRow:
                                InlineAddRow(
                                    placeholder: "Task title",
                                    buttonLabel: "Add task",
                                    onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                                    isAnyAddFieldActive: $isInlineAddFocused,
                                    verticalPadding: 8
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
                        if case .task(let t) = item, t.parentTaskId == nil { return sum + 52 }
                        return sum + 32
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
                    .font(.inter(.body))
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                if subtaskCount.total > 0 {
                    Text("\(subtaskCount.completed)/\(subtaskCount.total) subtasks")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            // Completion button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task {
                    await viewModel.toggleTaskCompletion(task, projectId: projectId)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(task.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
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

                ContextMenuItems.scheduleButton {
                    viewModel.selectedTaskForSchedule = task
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
                .font(.inter(.subheadline))
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
                    .font(.inter(.subheadline))
                    .foregroundColor(subtask.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedTaskForDetails = subtask
        }
        .contextMenu {
            if !subtask.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = subtask
                }

                ContextMenuItems.scheduleButton {
                    viewModel.selectedTaskForSchedule = subtask
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

// MARK: - Project Icon Shape

struct ProjectIconShape: View {
    var body: some View {
        Image("ProjectIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
