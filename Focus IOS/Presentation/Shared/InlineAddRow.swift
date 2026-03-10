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

    var textFont: Font = .helveticaNeue(.subheadline)
    var iconFont: Font = .helveticaNeue(.subheadline)
    var verticalPadding: CGFloat = 12
    var accentColor: Color = .secondary

    @State private var title = ""
    @State private var isEditing = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if isEditing {
                // Use axis: .vertical so Return inserts a newline (intercepted below)
                // instead of triggering .onSubmit which dismisses the keyboard.
                TextField(placeholder, text: $title, axis: .vertical)
                    .lineLimit(1)
                    .font(textFont)
                    .focused($isFocused)
                    .onChange(of: title) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        title = newValue.replacingOccurrences(of: "\n", with: "")
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
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Image(systemName: "plus")
                            .font(textFont)
                        Text(buttonLabel)
                            .font(textFont)
                    }
                    .foregroundColor(accentColor)
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

        let submittedTitle = trimmed
        isSubmitting = true
        title = ""

        _Concurrency.Task {
            await onSubmit(submittedTitle)
            isSubmitting = false
        }
    }
}
