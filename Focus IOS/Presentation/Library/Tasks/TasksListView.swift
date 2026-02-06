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
        }
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showingAddTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingAddTask) {
            AddTaskSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedTaskForEdit) { task in
            EditTaskSheet(task: task, viewModel: viewModel)
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

    private var taskList: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TaskRow(task: task, viewModel: viewModel)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteTask(task)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.selectedTaskForEdit = task
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.plain)
    }
}

struct TaskRow: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                if let completedDate = task.completedDate, task.isCompleted {
                    Text("Completed \(completedDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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

struct EditTaskSheet: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    @State private var taskTitle: String
    @FocusState private var isFocused: Bool

    init(task: FocusTask, viewModel: TaskListViewModel) {
        self.task = task
        self.viewModel = viewModel
        _taskTitle = State(initialValue: task.title)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Task title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .padding()

                Button("Save Changes") {
                    Task {
                        await viewModel.updateTask(task, newTitle: taskTitle)
                        viewModel.selectedTaskForEdit = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.selectedTaskForEdit = nil
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
