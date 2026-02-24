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

    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .target
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

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
                    Text("\(viewModel.selectedCount) item\(viewModel.selectedCount == 1 ? "" : "s") selected")
                        .font(.sf(.headline))
                }

                SwiftUI.Section("Section") {
                    Picker("Section", selection: $selectedSection) {
                        Text("Targets").tag(Section.target)
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
        let commitmentRepository = CommitmentRepository()
        let items = viewModel.selectedItems

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

            viewModel.exitEditMode()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }
}
