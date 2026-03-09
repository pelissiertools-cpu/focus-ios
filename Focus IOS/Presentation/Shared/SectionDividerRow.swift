//
//  SectionDividerRow.swift
//  Focus IOS
//

import SwiftUI

/// Reusable section divider row with an editable title and a thin line.
/// Used to visually categorize items in project and list pages.
struct SectionDividerRow: View {
    let section: FocusTask
    @Binding var editingSectionId: UUID?
    let onRename: (FocusTask, String) async -> Void
    let onDelete: (FocusTask) async -> Void

    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(
        section: FocusTask,
        editingSectionId: Binding<UUID?>,
        onRename: @escaping (FocusTask, String) async -> Void,
        onDelete: @escaping (FocusTask) async -> Void
    ) {
        self.section = section
        self._editingSectionId = editingSectionId
        self.onRename = onRename
        self.onDelete = onDelete
        _sectionTitle = State(initialValue: section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            TextField("Section name", text: $sectionTitle)
                .font(.inter(.headline, weight: .bold))
                .foregroundColor(.accentOrange)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit { saveSectionTitle() }
                .padding(.top, AppStyle.Spacing.section)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isEditing = true
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Section?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await onDelete(section)
                }
            }
        } message: {
            Text("This will remove the section header. Items will not be deleted.")
        }
        .onChange(of: editingSectionId) { _, newId in
            if newId == section.id {
                isEditing = true
                editingSectionId = nil
            }
        }
        .onChange(of: isEditing) { _, focused in
            if !focused { saveSectionTitle() }
        }
    }

    private func saveSectionTitle() {
        let trimmed = sectionTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            _Concurrency.Task {
                await onDelete(section)
            }
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await onRename(section, trimmed)
        }
    }
}
