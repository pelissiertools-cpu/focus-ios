//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TaskDetailsDrawer<VM: TaskEditingViewModel>: View {
    let task: FocusTask
    let commitment: Commitment?
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @State private var taskTitle: String
    @State private var showingCommitmentSheet = false
    @State private var newSubtaskTitle: String = ""
    @FocusState private var isFocused: Bool
    @FocusState private var isNewSubtaskFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSubtask: Bool {
        task.parentTaskId != nil
    }

    private var parentTask: FocusTask? {
        guard let parentId = task.parentTaskId else { return nil }
        return viewModel.findTask(byId: parentId)
    }

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
    }

    init(task: FocusTask, viewModel: VM, commitment: Commitment? = nil) {
        self.task = task
        self.viewModel = viewModel
        self.commitment = commitment
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
                } else {
                    // Subtasks Section (for parent tasks - show even if empty to allow adding)
                    SwiftUI.Section {
                        // Summary header
                        if !subtasks.isEmpty {
                            let completedCount = subtasks.filter { $0.isCompleted }.count
                            Label("\(completedCount)/\(subtasks.count) completed", systemImage: "checklist")
                                .foregroundColor(.secondary)
                        }

                        // Editable subtask rows
                        ForEach(subtasks) { subtask in
                            DrawerSubtaskRow(subtask: subtask, parentId: task.id, viewModel: viewModel)
                        }
                        .onDelete { indexSet in
                            deleteSubtasks(at: indexSet)
                        }

                        // Add subtask row
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.accentColor)
                            TextField("Add subtask", text: $newSubtaskTitle)
                                .focused($isNewSubtaskFocused)
                                .onSubmit {
                                    addSubtask()
                                }
                        }
                    } header: {
                        Text("Subtasks")
                    }
                }

                // Actions Section
                SwiftUI.Section {
                    // Commit to Focus (only shown when not already committed)
                    if commitment == nil {
                        Button {
                            showingCommitmentSheet = true
                        } label: {
                            Label("Commit to Focus", systemImage: "arrow.right.circle")
                        }
                    }

                    // Remove from Focus (only shown when committed)
                    if let commitment = commitment {
                        Button(role: .destructive) {
                            Task {
                                await focusViewModel.removeCommitment(commitment)
                                dismiss()
                            }
                        } label: {
                            Label("Remove from Focus", systemImage: "minus.circle")
                        }
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

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newSubtaskTitle
        newSubtaskTitle = ""
        Task {
            await viewModel.createSubtask(title: title, parentId: task.id)
        }
    }

    private func deleteSubtasks(at indexSet: IndexSet) {
        for index in indexSet {
            let subtask = subtasks[index]
            Task {
                await viewModel.deleteSubtask(subtask, parentId: task.id)
            }
        }
    }
}

// MARK: - Subtask Row for Drawer

struct DrawerSubtaskRow<VM: TaskEditingViewModel>: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: VM
    @State private var editingTitle: String
    @FocusState private var isEditing: Bool

    init(subtask: FocusTask, parentId: UUID, viewModel: VM) {
        self.subtask = subtask
        self.parentId = parentId
        self.viewModel = viewModel
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subtask.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)

            // Editable title
            TextField("Subtask", text: $editingTitle)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)
                .focused($isEditing)
                .onSubmit {
                    saveSubtaskTitle()
                }
                .onChange(of: isEditing) { editing in
                    if !editing {
                        saveSubtaskTitle()
                    }
                }
        }
    }

    private func saveSubtaskTitle() {
        guard editingTitle != subtask.title else { return }
        Task {
            await viewModel.updateTask(subtask, newTitle: editingTitle)
        }
    }
}
