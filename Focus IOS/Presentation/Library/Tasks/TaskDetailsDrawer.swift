//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TaskDetailsDrawer: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @State private var taskTitle: String
    @State private var showingCommitmentSheet = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSubtask: Bool {
        task.parentTaskId != nil
    }

    private var parentTask: FocusTask? {
        guard let parentId = task.parentTaskId else { return nil }
        return viewModel.tasks.first { $0.id == parentId }
    }

    private var subtasks: [FocusTask] {
        viewModel.subtasksMap[task.id] ?? []
    }

    init(task: FocusTask, viewModel: TaskListViewModel) {
        self.task = task
        self.viewModel = viewModel
        _taskTitle = State(initialValue: task.title)
    }

    var body: some View {
        NavigationView {
            List {
                // Edit Title Section
                SwiftUI.Section("Title") {
                    TextField("Task title", text: $taskTitle)
                        .focused($isFocused)
                        .onSubmit {
                            saveTitle()
                        }
                }

                // Info Section - shows parent or subtask count
                if isSubtask {
                    SwiftUI.Section("Parent Task") {
                        if let parent = parentTask {
                            Label(parent.title, systemImage: "arrow.up.circle")
                                .foregroundColor(.secondary)
                        } else {
                            Label("Subtask", systemImage: "arrow.up.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if !subtasks.isEmpty {
                    SwiftUI.Section("Subtasks") {
                        let completedCount = subtasks.filter { $0.isCompleted }.count
                        Label("\(completedCount)/\(subtasks.count) completed", systemImage: "checklist")
                            .foregroundColor(.secondary)
                    }
                }

                // Actions Section
                SwiftUI.Section {
                    // Commit to Focus (only for parent tasks and subtasks)
                    Button {
                        showingCommitmentSheet = true
                    } label: {
                        Label("Commit to Focus", systemImage: "arrow.right.circle")
                    }

                    // Delete
                    Button(role: .destructive) {
                        Task {
                            if isSubtask, let parentId = task.parentTaskId {
                                await viewModel.deleteSubtask(task, parentId: parentId)
                            } else {
                                await viewModel.deleteTask(task)
                            }
                            dismiss()
                        }
                    } label: {
                        Label(isSubtask ? "Delete Subtask" : "Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(isSubtask ? "Subtask Details" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        saveTitle()
                        dismiss()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
            .sheet(isPresented: $showingCommitmentSheet) {
                CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
            }
        }
    }

    private func saveTitle() {
        guard taskTitle != task.title else { return }
        Task {
            await viewModel.updateTask(task, newTitle: taskTitle)
        }
    }
}
