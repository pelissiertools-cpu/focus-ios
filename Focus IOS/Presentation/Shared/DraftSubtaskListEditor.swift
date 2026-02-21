//
//  DraftSubtaskListEditor.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Draft Subtask Entry

struct DraftSubtaskEntry: Identifiable {
    let id = UUID()
    var title: String = ""
    var isAISuggested: Bool = false
}

// MARK: - Draft Subtask List Editor

/// Reusable editor for a list of draft subtask entries.
/// Shows a divider, the subtask rows with remove buttons, and handles
/// return-key to create the next entry. Used in FocusTabView and LogTabView overlay bars.
struct DraftSubtaskListEditor: View {
    @Binding var subtasks: [DraftSubtaskEntry]
    var focusedSubtaskId: FocusState<UUID?>.Binding
    var onAddNew: () -> Void
    var placeholder: String = "Subtask"

    var body: some View {
        if !subtasks.isEmpty {
            Divider()
                .padding(.horizontal, 14)

            VStack(spacing: 14) {
                ForEach(subtasks) { subtask in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.sf(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField(placeholder, text: binding(for: subtask.id), axis: .vertical)
                            .font(.sf(.body))
                            .textFieldStyle(.plain)
                            .focused(focusedSubtaskId, equals: subtask.id)
                            .lineLimit(1...3)
                            .onChange(of: binding(for: subtask.id).wrappedValue) { _, newValue in
                                if newValue.contains("\n") {
                                    if let idx = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                                        subtasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                                    }
                                    onAddNew()
                                }
                            }

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                subtasks.removeAll { $0.id == subtask.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.sf(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { subtasks.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = subtasks.firstIndex(where: { $0.id == id }) {
                    subtasks[idx].title = newValue
                }
            }
        )
    }
}
