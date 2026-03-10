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
                .padding(.bottom, AppStyle.Spacing.comfortable)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Header

    private var projectHeader: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            // Edit mode: selection circle
            if viewModel.isEditMode && !project.isCompleted {
                Image(systemName: viewModel.selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedProjectIds.contains(project.id) ? .appRed : .secondary)
                    .accessibilityLabel(viewModel.selectedProjectIds.contains(project.id) ? "Selected" : "Select")
            }

            // Project icon
            ProjectIconShape()
                .frame(width: 32, height: 32)
                .foregroundColor(.orange)
                .opacity(project.isCompleted ? 0.4 : 1.0)

            // Title and progress
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Text(project.title)
                        .font(.inter(.title3, weight: .bold))
                        .lineLimit(1)
                        .strikethrough(project.isCompleted)
                        .foregroundColor(project.isCompleted ? .secondary : .primary)

                    if !project.isCompleted && taskProgress.total > 0 {
                        ProjectProgressRing(
                            completed: taskProgress.completed,
                            total: taskProgress.total,
                            size: 22
                        )
                    }
                }

                HStack(spacing: AppStyle.Spacing.section) {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Text("Task")
                            .font(.inter(.caption))
                        Text("\(taskProgress.completed)/\(taskProgress.total)")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: AppStyle.Spacing.tiny) {
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
                    .foregroundColor(Color.focusBlue)
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
                viewModel.selectedProjectForDetails = nil
                viewModel.selectedProjectForContent = project
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !viewModel.isEditMode {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.selectedProjectForContent = nil
                viewModel.selectedProjectForDetails = project
            }
        }
    }

}

// MARK: - Project Task Row

struct ProjectTaskRow: View {
    let task: FocusTask
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var showDeleteConfirmation = false

    private var isPending: Bool { viewModel.isPendingCompletion(task.id) }
    private var displayCompleted: Bool { task.isCompleted || isPending }

    private var subtaskCount: Int {
        let subtasks = viewModel.subtasksMap[task.id] ?? []
        return subtasks.count
    }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            // Task title + subtask count
            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(task.title)
                    .font(AppStyle.Typography.itemTitle)
                    .strikethrough(displayCompleted)
                    .foregroundColor(displayCompleted ? .secondary : .primary)

                if subtaskCount > 0 {
                    Text("\(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s")")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.iconButton, alignment: .leading)

            // Completion button
            Button {
                UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                viewModel.requestToggleTaskCompletion(task, projectId: projectId)
            } label: {
                Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(displayCompleted ? Color.focusBlue.opacity(0.6) : .gray)
                    .symbolEffect(.pulse, isActive: isPending)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayCompleted ? "Completed" : "Mark complete")
        }
        .padding(.vertical, AppStyle.Spacing.compact)
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

    private var isPending: Bool { viewModel.isPendingCompletion(subtask.id) }
    private var displayCompleted: Bool { subtask.isCompleted || isPending }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Text(subtask.title)
                .font(AppStyle.Typography.itemSubtitle)
                .strikethrough(displayCompleted)
                .foregroundColor(displayCompleted ? .secondary : .primary)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                viewModel.requestToggleSubtaskCompletion(subtask, parentId: parentId)
            } label: {
                Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(displayCompleted ? Color.focusBlue.opacity(0.6) : .gray)
                    .symbolEffect(.pulse, isActive: isPending)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayCompleted ? "Completed" : "Mark complete")
        }
        .padding(.vertical, AppStyle.Spacing.small)
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

// MARK: - Project Progress Ring

struct ProjectProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = AppStyle.Layout.smallIcon

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.focusBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
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
