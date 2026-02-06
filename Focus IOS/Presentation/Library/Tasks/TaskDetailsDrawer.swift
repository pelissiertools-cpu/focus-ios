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

    init(task: FocusTask, viewModel: TaskListViewModel) {
        self.task = task
        self.viewModel = viewModel
        _taskTitle = State(initialValue: task.title)
    }

    var body: some View {
        NavigationView {
            List {
                // Edit Title SwiftUI.Section
                SwiftUI.Section("Title") {
                    TextField("Task title", text: $taskTitle)
                        .focused($isFocused)
                        .onSubmit {
                            saveTitle()
                        }
                }

                // Subtasks SwiftUI.Section (Placeholder)
                SwiftUI.Section("Subtasks") {
                    Text("Coming soon")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                // Actions SwiftUI.Section
                SwiftUI.Section {
                    // Commit to Focus
                    Button {
                        showingCommitmentSheet = true
                    } label: {
                        Label("Commit to Focus", systemImage: "arrow.right.circle")
                    }

                    // Delete
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteTask(task)
                            dismiss()
                        }
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Task Details")
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
