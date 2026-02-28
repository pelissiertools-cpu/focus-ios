//
//  CommitmentSelectionSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

struct CommitmentSelectionSheet: View {
    let task: FocusTask
    @ObservedObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .todo
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var subtaskCount = 0
    @State private var isSaving = false

    // Track selected dates (toggled by tapping)
    @State private var selectedDates: Set<Date> = []
    // Track original commitments to know what to add/remove
    @State private var originalCommitments: [Commitment] = []

    private var isParentTask: Bool {
        task.parentTaskId == nil && subtaskCount > 0
    }

    private var hasChanges: Bool {
        let originalDates = Set(originalCommitments.map { normalizeDate($0.commitmentDate) })
        let currentDates = Set(selectedDates.map { normalizeDate($0) })
        return originalDates != currentDates
    }

    var body: some View {
        DrawerContainer(
            title: task.type == .list ? "Schedule List" : "Schedule Task",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await saveChanges() } },
                disabled: !hasChanges || isSaving
            )
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    // Task title card
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.inter(.headline))
                        if isParentTask {
                            let itemLabel = task.type == .list ? "item" : "subtask"
                            Text("Includes \(subtaskCount) \(itemLabel)\(subtaskCount == 1 ? "" : "s")")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Section picker + calendar card
                    VStack(spacing: 0) {
                        Picker("Section", selection: $selectedSection) {
                            Text("Focus").tag(Section.focus)
                            Text("To-Do").tag(Section.todo)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Divider()

                        UnifiedCalendarPicker(
                            selectedDates: $selectedDates,
                            selectedTimeframe: $selectedTimeframe
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                fetchSubtaskCount()
                fetchTaskCommitments()
            }
            .onChange(of: selectedTimeframe) {
                fetchTaskCommitments()
            }
            .onChange(of: selectedSection) {
                fetchTaskCommitments()
            }
        }
    }

    private func normalizeDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func saveChanges() async {
        isSaving = true

        do {
            let commitmentRepository = CommitmentRepository()

            // Fetch ALL commitments for this task (both sections) to check for conflicts
            let allCommitments = try await commitmentRepository.fetchCommitments(forTask: task.id)
            let otherSection: Section = selectedSection == .focus ? .todo : .focus

            let originalDates = Set(originalCommitments.map { normalizeDate($0.commitmentDate) })
            let currentDates = Set(selectedDates.map { normalizeDate($0) })

            // Find dates to add (in current but not in original)
            let datesToAdd = currentDates.subtracting(originalDates)

            // Find dates to remove (in original but not in current)
            let datesToRemove = originalDates.subtracting(currentDates)

            // Delete removed commitments from current section
            for date in datesToRemove {
                if let commitment = originalCommitments.first(where: { normalizeDate($0.commitmentDate) == date }) {
                    try await commitmentRepository.deleteCommitment(id: commitment.id)
                }
            }

            // For new dates, check if there's a conflict in the other section and remove it
            for date in datesToAdd {
                // Find and delete any conflicting commitment in the other section
                if let conflicting = allCommitments.first(where: {
                    $0.section == otherSection &&
                    $0.timeframe == selectedTimeframe &&
                    normalizeDate($0.commitmentDate) == normalizeDate(date)
                }) {
                    try await commitmentRepository.deleteCommitment(id: conflicting.id)
                }

                // Create the new commitment in selected section
                let commitment = Commitment(
                    userId: task.userId,
                    taskId: task.id,
                    timeframe: selectedTimeframe,
                    section: selectedSection,
                    commitmentDate: date,
                    sortOrder: 0
                )
                _ = try await commitmentRepository.createCommitment(commitment)
            }

            // Refresh focus view
            await focusViewModel.fetchCommitments()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }

    private func fetchSubtaskCount() {
        Task {
            do {
                let subtasks = try await TaskRepository().fetchSubtasks(parentId: task.id)
                await MainActor.run {
                    subtaskCount = subtasks.count
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func fetchTaskCommitments() {
        Task {
            do {
                let commitmentRepository = CommitmentRepository()
                let commitments = try await commitmentRepository.fetchCommitments(forTask: task.id)

                // Filter by current timeframe AND section
                let filtered = commitments.filter {
                    $0.timeframe == selectedTimeframe && $0.section == selectedSection
                }

                await MainActor.run {
                    originalCommitments = filtered
                    selectedDates = Set(filtered.map { $0.commitmentDate })
                }
            } catch {
                // Silently fail
            }
        }
    }
}
