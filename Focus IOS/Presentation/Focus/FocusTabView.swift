//
//  FocusTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import UniformTypeIdentifiers

struct FocusTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: FocusTabViewModel
    @State private var showCalendarPicker = false

    init() {
        _viewModel = StateObject(wrappedValue: FocusTabViewModel(authService: AuthService()))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date Navigator (above timeframe toggle)
                DateNavigator(
                    selectedDate: $viewModel.selectedDate,
                    timeframe: viewModel.selectedTimeframe,
                    onTap: { showCalendarPicker = true }
                )
                .onChange(of: viewModel.selectedDate) {
                    Task {
                        await viewModel.fetchCommitments()
                    }
                }

                // Timeframe Picker
                Picker("Timeframe", selection: $viewModel.selectedTimeframe) {
                    Text("Daily").tag(Timeframe.daily)
                    Text("Weekly").tag(Timeframe.weekly)
                    Text("Monthly").tag(Timeframe.monthly)
                    Text("Yearly").tag(Timeframe.yearly)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: viewModel.selectedTimeframe) {
                    Task {
                        await viewModel.fetchCommitments()
                    }
                }

                // Content
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Focus Section
                            SectionView(
                                title: "Focus",
                                section: .focus,
                                viewModel: viewModel
                            )

                            // Extra Section
                            SectionView(
                                title: "Extra",
                                section: .extra,
                                viewModel: viewModel
                            )
                        }
                        .padding()
                    }
                }
            }
            .task {
                await viewModel.fetchCommitments()
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
            .sheet(item: $viewModel.selectedTaskForDetails) { task in
                let commitment = viewModel.commitments.first { $0.taskId == task.id }
                TaskDetailsDrawer(task: task, viewModel: viewModel, commitment: commitment)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $viewModel.showCommitSheet) {
                if let commitment = viewModel.selectedCommitmentForCommit,
                   let task = viewModel.tasksMap[commitment.taskId] {
                    CommitSheet(
                        commitment: commitment,
                        task: task,
                        viewModel: viewModel
                    )
                }
            }
            .sheet(isPresented: $viewModel.showSubtaskCommitSheet) {
                if let subtask = viewModel.selectedSubtaskForCommit,
                   let parentCommitment = viewModel.selectedParentCommitmentForSubtaskCommit {
                    SubtaskCommitSheet(
                        subtask: subtask,
                        parentCommitment: parentCommitment,
                        viewModel: viewModel
                    )
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                SingleSelectCalendarPicker(
                    selectedDate: $viewModel.selectedDate,
                    timeframe: viewModel.selectedTimeframe
                )
            }
            .sheet(isPresented: $viewModel.showAddTaskSheet) {
                AddTaskToFocusSheet(
                    section: viewModel.addTaskSection,
                    viewModel: viewModel
                )
            }
        }
    }
}

struct SectionView: View {
    let title: String
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    @State private var isTargeted = false

    var sectionCommitments: [Commitment] {
        viewModel.commitments.filter { commitment in
            commitment.section == section &&
            viewModel.isSameTimeframe(
                commitment.commitmentDate,
                timeframe: viewModel.selectedTimeframe,
                selectedDate: viewModel.selectedDate
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 12) {
                // Section icon
                Image(systemName: section == .focus ? "target" : "tray.full")
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                // Count display
                if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                    Text("\(sectionCommitments.count)/\(maxTasks)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if !sectionCommitments.isEmpty {
                    Text("\(sectionCommitments.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Collapse chevron (Extra section only) - next to title/count
                if section == .extra {
                    Image(systemName: viewModel.isSectionCollapsed(section) ? "chevron.right" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Add button (far right)
                Button {
                    viewModel.addTaskSection = section
                    viewModel.showAddTaskSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(section == .focus && !viewModel.canAddTask(to: .focus))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if section == .extra {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleSectionCollapsed(section)
                    }
                }
            }

            // Committed Tasks (hidden when collapsed)
            if !viewModel.isSectionCollapsed(section) {
                if sectionCommitments.isEmpty {
                    Text("No to-dos yet. Tap + to add one.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    VStack(spacing: 0) {
                        ForEach(sectionCommitments) { commitment in
                            if let task = viewModel.tasksMap[commitment.taskId] {
                                CommitmentRow(commitment: commitment, task: task, viewModel: viewModel)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            let currentCommitments = viewModel.commitments
            provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let idString = string as? String,
                      let id = UUID(uuidString: idString),
                      let commitment = currentCommitments.first(where: { $0.id == id }),
                      commitment.section != section else { return }

                Task { @MainActor in
                    await viewModel.moveCommitmentToSection(commitment, to: section)
                }
            }
            return true
        }
    }
}

struct AddTaskToFocusSheet: View {
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var taskTitle = ""
    @FocusState private var isFocused: Bool
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Task title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .padding()
                    .onSubmit {
                        saveTask()
                    }

                Spacer()
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { saveTask() }
                        .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func saveTask() {
        guard !taskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        Task {
            await viewModel.createTaskWithCommitment(title: taskTitle, section: section)
            dismiss()
        }
    }
}

struct CommitmentRow: View {
    let commitment: Commitment
    let task: FocusTask
    @ObservedObject var viewModel: FocusTabViewModel

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
    }

    private var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    private var isExpanded: Bool {
        viewModel.isExpanded(task.id)
    }

    private var childCount: Int {
        viewModel.childCount(for: commitment.id)
    }

    /// Can break down if: not daily (child commitments can also break down)
    private var canBreakdown: Bool {
        commitment.canBreakdown
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main task row - matching ExpandableTaskRow style
            HStack(spacing: 12) {
                // Drag handle (left side)
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .onDrag {
                        NSItemProvider(object: commitment.id.uuidString as NSString)
                    }

                // Child commitment indicator (indentation)
                if commitment.isChildCommitment {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)

                    // Subtask count indicator
                    if hasSubtasks {
                        let completedCount = subtasks.filter { $0.isCompleted }.count
                        Text("\(completedCount)/\(subtasks.count) subtasks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Child commitment count indicator
                    if childCount > 0 {
                        Text("\(childCount) broken down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasSubtasks {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleExpanded(task.id)
                        }
                    }
                }
                .onLongPressGesture {
                    viewModel.selectedTaskForDetails = task
                }

                // Commit button (for non-daily commitments)
                if canBreakdown {
                    Button {
                        viewModel.selectedCommitmentForCommit = commitment
                        viewModel.showCommitSheet = true
                    } label: {
                        Image(systemName: "arrow.down.forward.circle")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

                // Completion button (right side for thumb access)
                Button {
                    Task {
                        await viewModel.toggleTaskCompletion(task)
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(commitment.isChildCommitment
                ? Color(.tertiarySystemBackground)
                : Color(.systemBackground))

            // Subtasks (shown when expanded)
            if isExpanded && hasSubtasks {
                VStack(spacing: 0) {
                    ForEach(subtasks) { subtask in
                        FocusSubtaskRow(subtask: subtask, parentId: task.id, parentCommitment: commitment, viewModel: viewModel)
                    }
                }
                .padding(.leading, 32)
                .background(Color(.systemBackground))
            }
        }
    }
}

struct FocusSubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    let parentCommitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel

    /// Check if this subtask already has its own commitment
    private var hasOwnCommitment: Bool {
        viewModel.commitments.contains { $0.taskId == subtask.id }
    }

    /// Can break down if parent's timeframe is not daily and subtask doesn't have own commitment yet
    private var canBreakdown: Bool {
        parentCommitment.timeframe != .daily && !hasOwnCommitment
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.subheadline)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            // Commit button for subtasks that can be committed to lower timeframes
            if canBreakdown {
                Button {
                    viewModel.selectedSubtaskForCommit = subtask
                    viewModel.selectedParentCommitmentForSubtaskCommit = parentCommitment
                    viewModel.showSubtaskCommitSheet = true
                } label: {
                    Image(systemName: "arrow.down.forward.circle")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

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
    }
}

#Preview {
    FocusTabView()
}
