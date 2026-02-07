//
//  FocusTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct FocusTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: FocusTabViewModel

    init() {
        _viewModel = StateObject(wrappedValue: FocusTabViewModel(authService: AuthService()))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Timeframe Picker
                Picker("Timeframe", selection: $viewModel.selectedTimeframe) {
                    Text("Daily").tag(Timeframe.daily)
                    Text("Weekly").tag(Timeframe.weekly)
                    Text("Monthly").tag(Timeframe.monthly)
                    Text("Yearly").tag(Timeframe.yearly)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: viewModel.selectedTimeframe) { _ in
                    Task {
                        await viewModel.fetchCommitments()
                    }
                }

                // Date Selection based on timeframe
                Group {
                    switch viewModel.selectedTimeframe {
                    case .daily:
                        DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                            .padding(.horizontal)
                    case .weekly:
                        WeekPicker(selectedDate: $viewModel.selectedDate)
                            .padding(.horizontal)
                    case .monthly:
                        MonthPicker(selectedDate: $viewModel.selectedDate)
                            .padding(.horizontal)
                    case .yearly:
                        YearPicker(selectedDate: $viewModel.selectedDate)
                            .padding(.horizontal)
                    }
                }
                .onChange(of: viewModel.selectedDate) { _ in
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
            .navigationTitle("Focus")
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
        }
    }
}

struct SectionView: View {
    let title: String
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel

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
            // Section Header with Count
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                    Text("\(sectionCommitments.count)/\(maxTasks)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Committed Tasks
            if sectionCommitments.isEmpty {
                Text("No tasks committed yet")
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
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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

    var body: some View {
        VStack(spacing: 0) {
            // Main task row - matching ExpandableTaskRow style
            HStack(spacing: 12) {
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
            .background(Color(.systemBackground))

            // Subtasks (shown when expanded)
            if isExpanded && hasSubtasks {
                VStack(spacing: 0) {
                    ForEach(subtasks) { subtask in
                        FocusSubtaskRow(subtask: subtask, parentId: task.id, viewModel: viewModel)
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
    @ObservedObject var viewModel: FocusTabViewModel

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
    }
}

#Preview {
    FocusTabView()
}
