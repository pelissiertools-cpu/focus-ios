//
//  TasksListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TasksListView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: TaskListViewModel

    init() {
        // Initialize with a placeholder, will be properly set in onAppear
        _viewModel = StateObject(wrappedValue: TaskListViewModel(authService: AuthService()))
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading tasks...")
            } else if viewModel.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }

            // Floating add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        viewModel.showingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $viewModel.showingAddTask) {
            AddTaskSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .task {
            // Reinitialize viewModel with proper authService from environment
            if viewModel.tasks.isEmpty && !viewModel.isLoading {
                await viewModel.fetchTasks()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Tasks Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to add your first task")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var uncompletedTasks: [FocusTask] {
        viewModel.tasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [FocusTask] {
        viewModel.tasks.filter { $0.isCompleted }
    }

    private var taskList: some View {
        List {
            // Uncompleted tasks
            ForEach(uncompletedTasks) { task in
                VStack(spacing: 0) {
                    ExpandableTaskRow(task: task, viewModel: viewModel)

                    if viewModel.isExpanded(task.id) {
                        SubtasksList(parentTask: task, viewModel: viewModel)
                        InlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteTask(task)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // Done pill (when there are completed tasks)
            if !completedTasks.isEmpty {
                LibraryDonePillView(completedTasks: completedTasks, viewModel: viewModel)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Library Done Pill View

struct LibraryDonePillView: View {
    let completedTasks: [FocusTask]
    @ObservedObject var viewModel: TaskListViewModel
    @State private var showClearConfirmation = false

    private var isExpanded: Bool {
        !viewModel.isDoneSubsectionCollapsed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Done pill header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleDoneSubsectionCollapsed()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("(\(completedTasks.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Clear list pill button (only visible when expanded)
                    if isExpanded {
                        Button {
                            showClearConfirmation = true
                        } label: {
                            Text("Clear list")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded completed tasks
            if isExpanded {
                ForEach(completedTasks) { task in
                    VStack(spacing: 0) {
                        Divider()
                        ExpandableTaskRow(task: task, viewModel: viewModel)

                        if viewModel.isExpanded(task.id) {
                            SubtasksList(parentTask: task, viewModel: viewModel)
                            InlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteTask(task)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .alert("Clear completed tasks?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearCompletedTasks()
                }
            }
        } message: {
            Text("This will permanently delete \(completedTasks.count) completed task\(completedTasks.count == 1 ? "" : "s").")
        }
    }
}

// MARK: - Expandable Task Row

struct ExpandableTaskRow: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Task content - tap to expand/collapse
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                // Subtask count indicator
                if let subtasks = viewModel.subtasksMap[task.id], !subtasks.isEmpty {
                    let completedCount = subtasks.filter { $0.isCompleted }.count
                    Text("\(completedCount)/\(subtasks.count) subtasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await viewModel.toggleExpanded(task.id)
                }
            }
            .onLongPressGesture {
                viewModel.selectedTaskForDetails = task
            }

            // Completion button (right side for thumb access)
            Button {
                Task {
                    await viewModel.toggleCompletion(task)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Subtasks List

struct SubtasksList: View {
    let parentTask: FocusTask
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingSubtasks.contains(parentTask.id) {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(viewModel.getSubtasks(for: parentTask.id)) { subtask in
                    SubtaskRow(subtask: subtask, parentId: parentTask.id, viewModel: viewModel)
                }
            }
        }
        .padding(.leading, 32)
    }
}

// MARK: - Subtask Row

struct SubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.subheadline)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox on right for thumb access
            Button {
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(subtask.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onLongPressGesture {
            viewModel.selectedTaskForDetails = subtask
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSubtask(subtask, parentId: parentId)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Inline Add Subtask Row

struct InlineAddSubtaskRow: View {
    let parentId: UUID
    @ObservedObject var viewModel: TaskListViewModel
    @State private var newSubtaskTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Subtask title", text: $newSubtaskTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitSubtask()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline)
                        Text("Add")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 32)
    }

    private func submitSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        Task {
            await viewModel.createSubtask(title: title, parentId: parentId)
            newSubtaskTitle = ""
            // Keep editing mode open for adding more subtasks
        }
    }
}

struct AddTaskSheet: View {
    @ObservedObject var viewModel: TaskListViewModel
    @State private var taskTitle = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Task title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .padding()

                Button("Add Task") {
                    Task {
                        await viewModel.createTask(title: taskTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showingAddTask = false
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

#Preview {
    NavigationView {
        TasksListView()
            .environmentObject(AuthService())
    }
}
