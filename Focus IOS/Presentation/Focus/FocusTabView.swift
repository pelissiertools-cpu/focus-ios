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

                // Date Picker
                DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .padding(.horizontal)
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
        }
    }
}

struct SectionView: View {
    let title: String
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel

    var sectionCommitments: [Commitment] {
        viewModel.commitments.filter { $0.section == section }
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
                ForEach(sectionCommitments) { commitment in
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        CommitmentRow(commitment: commitment, task: task, viewModel: viewModel)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)

                Text(commitment.timeframe.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Remove button
            Button(role: .destructive) {
                Task {
                    await viewModel.removeCommitment(commitment)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    FocusTabView()
}
