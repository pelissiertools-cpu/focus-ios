//
//  BreakdownDrawer.swift
//  Focus IOS
//

import SwiftUI

struct BreakdownDrawer: View {
    @StateObject private var viewModel: BreakdownViewModel
    @State private var newSubtaskTitle = ""
    @FocusState private var isNewSubtaskFocused: Bool
    @Environment(\.dismiss) private var dismiss

    let onSaveComplete: () -> Void

    init(parentTask: FocusTask, userId: UUID, onSaveComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: BreakdownViewModel(parentTask: parentTask, userId: userId))
        self.onSaveComplete = onSaveComplete
    }

    var body: some View {
        NavigationView {
            ZStack {
                content
            }
            .navigationTitle("Break Down Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        _Concurrency.Task { @MainActor in
                            let success = await viewModel.saveSubtasks()
                            if success {
                                onSaveComplete()
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.suggestions.isEmpty || viewModel.isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if let error = viewModel.errorMessage, viewModel.suggestions.isEmpty {
            errorView(error)
        } else {
            suggestionsList
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Breaking down task...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                _Concurrency.Task { @MainActor in
                    await viewModel.generateSuggestions()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        List {
            // Parent task header
            SwiftUI.Section {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .foregroundColor(.accentColor)
                    Text(viewModel.parentTask.title)
                        .font(.headline)
                }
            }

            // Suggestions
            SwiftUI.Section {
                ForEach(viewModel.suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        onUpdate: { newTitle in
                            viewModel.updateSuggestion(suggestion, newTitle: newTitle)
                        },
                        onDelete: {
                            withAnimation { viewModel.removeSuggestion(suggestion) }
                        }
                    )
                }
                .onMove { source, destination in
                    viewModel.moveSuggestion(from: source, to: destination)
                }

                // Add subtask row
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                    TextField("Add subtask", text: $newSubtaskTitle)
                        .focused($isNewSubtaskFocused)
                        .onSubmit {
                            addManualSubtask()
                        }
                }
            } header: {
                HStack {
                    Text("Subtasks")
                    Spacer()
                    if !viewModel.suggestions.isEmpty {
                        Text("\(viewModel.suggestions.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Regenerate button
            SwiftUI.Section {
                Button {
                    _Concurrency.Task { @MainActor in
                        await viewModel.generateSuggestions()
                    }
                } label: {
                    HStack {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                        if viewModel.isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if viewModel.suggestions.isEmpty && !viewModel.isLoading {
                await viewModel.generateSuggestions()
            }
        }
    }

    private func addManualSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        viewModel.addManualSubtask(title: newSubtaskTitle)
        newSubtaskTitle = ""
        isNewSubtaskFocused = true
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let suggestion: SubtaskSuggestion
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var editingTitle: String
    @FocusState private var isEditing: Bool

    init(suggestion: SubtaskSuggestion, onUpdate: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.suggestion = suggestion
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _editingTitle = State(initialValue: suggestion.title)
    }

    var body: some View {
        HStack(spacing: 12) {
            DragHandleView()

            TextField("Subtask", text: $editingTitle)
                .focused($isEditing)
                .onSubmit { commitEdit() }
                .onChange(of: isEditing) { _, editing in
                    if !editing { commitEdit() }
                }

            if suggestion.isAISuggested {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.6))
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func commitEdit() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            editingTitle = suggestion.title
        } else if trimmed != suggestion.title {
            onUpdate(trimmed)
        }
    }
}
