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
    @State private var selectedSection: Section = .focus
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
        NavigationView {
            Form {
                SwiftUI.Section("Task") {
                    Text(task.title)
                        .font(.headline)

                    if isParentTask {
                        Text("Includes \(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                SwiftUI.Section("Section") {
                    Picker("Section", selection: $selectedSection) {
                        Text("Focus").tag(Section.focus)
                        Text("Extra").tag(Section.extra)
                    }
                    .pickerStyle(.segmented)
                }

                SwiftUI.Section("Select Dates") {
                    UnifiedCalendarPicker(
                        selectedDates: $selectedDates,
                        selectedTimeframe: $selectedTimeframe
                    )
                }
            }
            .navigationTitle("Commit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                    .fontWeight(.semibold)
                }
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
            .onChange(of: selectedTimeframe) { _ in
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

            let originalDates = Set(originalCommitments.map { normalizeDate($0.commitmentDate) })
            let currentDates = Set(selectedDates.map { normalizeDate($0) })

            // Find dates to add (in current but not in original)
            let datesToAdd = currentDates.subtracting(originalDates)

            // Find dates to remove (in original but not in current)
            let datesToRemove = originalDates.subtracting(currentDates)

            // Delete removed commitments
            for date in datesToRemove {
                if let commitment = originalCommitments.first(where: { normalizeDate($0.commitmentDate) == date }) {
                    try await commitmentRepository.deleteCommitment(id: commitment.id)
                }
            }

            // Create new commitments
            for date in datesToAdd {
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

                // Filter by current timeframe
                let filtered = commitments.filter { $0.timeframe == selectedTimeframe }

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
