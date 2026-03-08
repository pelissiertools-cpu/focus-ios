//
//  CreateGoalDrawer.swift
//  Focus IOS
//

import SwiftUI

struct CreateGoalDrawer: View {
    @ObservedObject var viewModel: GoalsViewModel
    @State private var goalTitle: String = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
    @State private var hasDueDate: Bool = true
    @State private var draftSteps: [DraftSubtaskEntry] = []
    @State private var isGeneratingBreakdown: Bool = false
    @State private var hasGeneratedBreakdown: Bool = false
    @State private var showNewStepField: Bool = false
    @State private var newStepTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewStepFocused: Bool
    @FocusState private var focusedStepId: UUID?
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !goalTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        DrawerContainer(
            title: "New Goal",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveGoal()
            }, highlighted: canSave)
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Goal Title
                    goalTitleCard

                    // MARK: - Deadline
                    deadlineCard

                    // MARK: - Next Steps
                    nextStepsCard
                }
                .padding(.bottom, 20)
            }
            .background(.clear)
        }
    }

    // MARK: - Goal Title Card

    @ViewBuilder
    private var goalTitleCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's the goal?")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            TextField("Describe your goal", text: $goalTitle, axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }

    // MARK: - Deadline Card

    @ViewBuilder
    private var deadlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("By when?")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $hasDueDate)
                    .labelsHidden()
                    .tint(.focusBlue)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if hasDueDate {
                DatePicker(
                    "",
                    selection: $dueDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Next Steps Card

    @ViewBuilder
    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Next Steps")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()

                if !goalTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        generateNextSteps()
                    } label: {
                        HStack(spacing: 6) {
                            if isGeneratingBreakdown {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                    .font(.inter(.subheadline, weight: .semiBold))
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Steps"))
                                .font(.inter(.caption, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 14) {
                // Draft steps list
                ForEach(draftSteps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.inter(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Step", text: stepBinding(for: step.id))
                            .font(.inter(.body))
                            .textFieldStyle(.plain)
                            .focused($focusedStepId, equals: step.id)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                draftSteps.removeAll { $0.id == step.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // New step entry
                if showNewStepField || !newStepTitle.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.inter(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Step", text: $newStepTitle)
                            .font(.inter(.body))
                            .textFieldStyle(.plain)
                            .focused($isNewStepFocused)
                            .onAppear { isNewStepFocused = true }
                            .onSubmit { addNewStep() }

                        Button {
                            newStepTitle = ""
                            showNewStepField = false
                            isNewStepFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // "+ Step" button
                HStack {
                    Button {
                        if !newStepTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                            addNewStep()
                        }
                        showNewStepField = true
                        isNewStepFocused = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.inter(.caption))
                            Text("Step")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func generateNextSteps() {
        isGeneratingBreakdown = true
        let existingTitles = draftSteps.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: goalTitle,
                    description: nil,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    let manualDrafts = draftSteps.filter { !$0.isAISuggested }
                    draftSteps = manualDrafts + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail — user can retry or add manually
            }
            isGeneratingBreakdown = false
        }
    }

    private func addNewStep() {
        let trimmed = newStepTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        draftSteps.append(DraftSubtaskEntry(title: trimmed))
        newStepTitle = ""
        isNewStepFocused = true
    }

    private func saveGoal() {
        // Capture any pending new step
        let trimmedNewStep = newStepTitle.trimmingCharacters(in: .whitespaces)
        if !trimmedNewStep.isEmpty {
            draftSteps.append(DraftSubtaskEntry(title: trimmedNewStep))
        }

        let deadline = hasDueDate ? dueDate : nil

        _Concurrency.Task {
            let goalId = await viewModel.saveNewGoal(
                title: goalTitle,
                dueDate: deadline,
                draftSteps: draftSteps
            )
            if goalId != nil {
                dismiss()
            }
        }
    }

    private func stepBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSteps.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = draftSteps.firstIndex(where: { $0.id == id }) {
                    draftSteps[idx].title = newValue
                }
            }
        )
    }
}
