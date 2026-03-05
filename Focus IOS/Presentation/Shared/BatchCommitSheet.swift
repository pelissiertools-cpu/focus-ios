//
//  BatchCommitSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct BatchCommitSheet<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    /// Optional override: supply tasks directly instead of using `viewModel.selectedItems`
    var tasks: [FocusTask]?
    /// Optional callback when scheduling completes (instead of `viewModel.exitEditMode()`)
    var onComplete: (() -> Void)?
    /// Optional callback to intercept scheduling instead of writing to DB
    var onBatchSchedule: (([FocusTask], Timeframe, Section, Set<Date>) -> Void)? = nil

    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .todo
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var itemCount: Int { tasks?.count ?? viewModel.selectedCount }

    var body: some View {
        DrawerContainer(
            title: "Schedule Items",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await saveCommitments() } },
                disabled: selectedDates.isEmpty || isSaving
            )
        ) {
            Form {
                SwiftUI.Section("Items") {
                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s") selected")
                        .font(.inter(.headline))
                }

                SwiftUI.Section("Section") {
                    Picker("Section", selection: $selectedSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
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
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveCommitments() async {
        isSaving = true
        let items = tasks ?? viewModel.selectedItems

        if let onBatchSchedule {
            let normalizedDates = Set(selectedDates.map { Calendar.current.startOfDay(for: $0) })
            onBatchSchedule(items, selectedTimeframe, selectedSection, normalizedDates)
            if let onComplete {
                onComplete()
            } else {
                viewModel.exitEditMode()
            }
            dismiss()
            isSaving = false
            return
        }

        let commitmentRepository = CommitmentRepository()

        do {
            for item in items {
                for date in selectedDates {
                    let commitment = Commitment(
                        userId: item.userId,
                        taskId: item.id,
                        timeframe: selectedTimeframe,
                        section: selectedSection,
                        commitmentDate: Calendar.current.startOfDay(for: date),
                        sortOrder: 0
                    )
                    _ = try await commitmentRepository.createCommitment(commitment)
                }
            }

            await focusViewModel.fetchCommitments()
            await viewModel.fetchCommittedTaskIds()

            if let onComplete {
                onComplete()
            } else {
                viewModel.exitEditMode()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }
}
