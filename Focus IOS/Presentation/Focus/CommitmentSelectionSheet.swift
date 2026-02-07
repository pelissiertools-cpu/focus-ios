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
    @State private var selectedDate: Date = Date()
    @State private var currentTaskCount = 0
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                SwiftUI.Section("Task") {
                    Text(task.title)
                        .font(.headline)
                }

                SwiftUI.Section("Section") {
                    Picker("Section", selection: $selectedSection) {
                        Text("Focus").tag(Section.focus)
                        Text("Extra").tag(Section.extra)
                    }
                    .pickerStyle(.segmented)

                    // Show task limits
                    if let maxTasks = selectedSection.maxTasks(for: selectedTimeframe) {
                        HStack {
                            Text("Task Limit:")
                            Spacer()
                            Text("\(currentTaskCount)/\(maxTasks)")
                                .foregroundColor(currentTaskCount >= maxTasks ? .red : .secondary)
                        }
                        .font(.caption)
                    }
                }

                SwiftUI.Section("Select Date") {
                    UnifiedCalendarPicker(
                        selectedDate: $selectedDate,
                        selectedTimeframe: $selectedTimeframe
                    )
                }

                SwiftUI.Section {
                    Button("Commit to Focus") {
                        Task {
                            await commitTask()
                        }
                    }
                    .disabled(!canCommit())
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
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                updateTaskCount()
            }
            .onChange(of: selectedTimeframe) { _ in
                updateTaskCount()
            }
            .onChange(of: selectedSection) { _ in
                updateTaskCount()
            }
            .onChange(of: selectedDate) { _ in
                updateTaskCount()
            }
        }
    }

    private func canCommit() -> Bool {
        focusViewModel.canAddTask(to: selectedSection, timeframe: selectedTimeframe, date: selectedDate)
    }

    private func commitTask() async {
        guard canCommit() else {
            errorMessage = "Cannot add more tasks to \(selectedSection.rawValue) section. Limit reached."
            showError = true
            return
        }

        do {
            let commitment = Commitment(
                userId: task.userId,
                taskId: task.id,
                timeframe: selectedTimeframe,
                section: selectedSection,
                commitmentDate: selectedDate,
                sortOrder: 0
            )

            _ = try await CommitmentRepository().createCommitment(commitment)

            // Refresh focus view
            await focusViewModel.fetchCommitments()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func updateTaskCount() {
        currentTaskCount = focusViewModel.taskCount(
            for: selectedSection,
            timeframe: selectedTimeframe,
            date: selectedDate
        )
    }
}
