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
    @Binding var isCollapsed: Bool
    let onRename: (FocusTask, String) async -> Void
    let onDelete: (FocusTask) async -> Void

    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(
        section: FocusTask,
        editingSectionId: Binding<UUID?>,
        isCollapsed: Binding<Bool>,
        onRename: @escaping (FocusTask, String) async -> Void,
        onDelete: @escaping (FocusTask) async -> Void
    ) {
        self.section = section
        self._editingSectionId = editingSectionId
        self._isCollapsed = isCollapsed
        self.onRename = onRename
        self.onDelete = onDelete
        _sectionTitle = State(initialValue: section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                TextField("Section name", text: $sectionTitle)
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.focusBlue)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit { saveSectionTitle() }
                    .allowsHitTesting(isEditing)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.inter(.caption, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.easeInOut(duration: 0.2), value: isCollapsed)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCollapsed.toggle()
                        }
                    }
            }
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
        .onAppear {
            if editingSectionId == section.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isEditing = true
                    editingSectionId = nil
                }
            }
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
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await onRename(section, trimmed)
        }
    }
}
