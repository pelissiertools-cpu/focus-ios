//
//  ScheduleDrawer.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Filter Type

enum ScheduleFilter: Equatable {
    case today
    case all
    case category(UUID)
}

// MARK: - Schedule Drawer

struct ScheduleDrawer: View {
    @ObservedObject var viewModel: FocusTabViewModel
    @State private var selectedFilter: ScheduleFilter = .today
    @State private var categories: [Category] = []

    private let categoryRepository = CategoryRepository()

    // MARK: - Computed Properties

    private var titleText: String {
        switch selectedFilter {
        case .today:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "Today, \(formatter.string(from: viewModel.selectedDate))"
        case .all:
            return "All Tasks"
        case .category(let id):
            return categories.first(where: { $0.id == id })?.name ?? "Category"
        }
    }

    private var dailyCommitments: [Commitment] {
        viewModel.commitments.filter { commitment in
            commitment.timeframe == .daily &&
            viewModel.isSameTimeframe(
                commitment.commitmentDate,
                timeframe: .daily,
                selectedDate: viewModel.selectedDate
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(titleText)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Add a task row
            Button {
                viewModel.addTaskSection = .focus
                viewModel.showAddTaskSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("Add a task")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 12)

            // Task list
            ScrollView {
                VStack(spacing: 8) {
                    if selectedFilter == .today {
                        todayTasksList
                    } else {
                        // Placeholder for All / Category filters
                        Text("No tasks")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 0)

            // Bottom filter pills
            filterPills
                .padding(.bottom, 8)
        }
        .task {
            await fetchCategories()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Today Tasks List

    @ViewBuilder
    private var todayTasksList: some View {
        ForEach(dailyCommitments) { commitment in
            if let task = viewModel.tasksMap[commitment.taskId] {
                let subtasks = viewModel.getSubtasks(for: task.id)
                let hasSubtasks = !subtasks.isEmpty
                let isExpanded = viewModel.isExpanded(task.id)

                VStack(spacing: 0) {
                    // Main task row
                    HStack(spacing: 12) {
                        Button {
                            _Concurrency.Task { @MainActor in
                                await viewModel.toggleTaskCompletion(task)
                            }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(task.isCompleted ? .green : .gray)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.body)
                                .strikethrough(task.isCompleted)
                                .foregroundColor(task.isCompleted ? .secondary : .primary)

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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleExpanded(task.id)
                            }
                        }
                        .onLongPressGesture {
                            viewModel.selectedTaskForDetails = task
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    // Subtasks (shown when expanded)
                    if isExpanded {
                        VStack(spacing: 0) {
                            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                                FocusSubtaskRow(
                                    subtask: subtask,
                                    parentId: task.id,
                                    parentCommitment: commitment,
                                    viewModel: viewModel
                                )

                                if index < subtasks.count - 1 {
                                    Divider()
                                }
                            }
                            Divider()
                            FocusInlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                        }
                        .padding(.leading, 32)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(title: "Today", isSelected: selectedFilter == .today) {
                    selectedFilter = .today
                }

                FilterPill(title: "All", isSelected: selectedFilter == .all) {
                    selectedFilter = .all
                }

                ForEach(categories) { category in
                    FilterPill(
                        title: category.name,
                        isSelected: selectedFilter == .category(category.id)
                    ) {
                        selectedFilter = .category(category.id)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data

    private func fetchCategories() async {
        do {
            categories = try await categoryRepository.fetchCategories(type: .task)
        } catch {
            // Silent fail — pills just won't show categories
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}
