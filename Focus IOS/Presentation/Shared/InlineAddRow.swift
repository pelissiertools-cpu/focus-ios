//
//  InlineAddRow.swift
//  Focus IOS
//

import SwiftUI

/// Reusable inline row that toggles between a "+ Add …" button and a text field.
/// Used for adding subtasks, list items, and project tasks across the app.
struct InlineAddRow: View {
    let placeholder: String
    let buttonLabel: String
    let onSubmit: (String) async -> Void
    var isAnyAddFieldActive: Binding<Bool>?

    var textFont: Font = .inter(.subheadline)
    var iconFont: Font = .inter(.subheadline)
    var verticalPadding: CGFloat = 12

    @State private var title = ""
    @State private var isEditing = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField(placeholder, text: $title)
                    .font(textFont)
                    .focused($isFocused)
                    .onSubmit {
                        submit()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(iconFont)
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(textFont)
                        Text(buttonLabel)
                            .font(textFont)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, verticalPadding)
        .onChange(of: isFocused) { _, focused in
            if focused {
                isAnyAddFieldActive?.wrappedValue = true
            } else if !isSubmitting {
                isAnyAddFieldActive?.wrappedValue = false
                isEditing = false
                title = ""
            }
        }
        .onDisappear {
            isAnyAddFieldActive?.wrappedValue = false
        }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            isEditing = false
            return
        }

        isSubmitting = true
        _Concurrency.Task {
            await onSubmit(trimmed)
            title = ""
            isFocused = true
            isSubmitting = false
        }
    }
}
