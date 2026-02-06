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
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                SwiftUI.Section("Task") {
                    Text(task.title)
                        .font(.headline)
                }

                SwiftUI.Section("Timeframe") {
                    Picker("Timeframe", selection: $selectedTimeframe) {
                        Text("Daily").tag(Timeframe.daily)
                        Text("Weekly").tag(Timeframe.weekly)
                        Text("Monthly").tag(Timeframe.monthly)
                        Text("Yearly").tag(Timeframe.yearly)
                    }
                    .pickerStyle(.segmented)
                }

                SwiftUI.Section("Section") {
                    Picker("Section", selection: $selectedSection) {
                        Text("Focus").tag(Section.focus)
                        Text("Extra").tag(Section.extra)
                    }
                    .pickerStyle(.segmented)

                    // Show task limits
                    if let maxTasks = selectedSection.maxTasks(for: selectedTimeframe) {
                        let currentCount = focusViewModel.taskCount(for: selectedSection, timeframe: selectedTimeframe, date: selectedDate)
                        HStack {
                            Text("Task Limit:")
                            Spacer()
                            Text("\(currentCount)/\(maxTasks)")
                                .foregroundColor(currentCount >= maxTasks ? .red : .secondary)
                        }
                        .font(.caption)
                    }
                }

                SwiftUI.Section("Commitment Date") {
                    switch selectedTimeframe {
                    case .daily:
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    case .weekly:
                        WeekPicker(selectedDate: $selectedDate)
                    case .monthly:
                        MonthPicker(selectedDate: $selectedDate)
                    case .yearly:
                        YearPicker(selectedDate: $selectedDate)
                    }
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
}
