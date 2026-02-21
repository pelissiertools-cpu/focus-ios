//
//  CategoryEditDrawer.swift
//  Focus IOS
//

import SwiftUI

struct CategoryEditDrawer<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @Environment(\.dismiss) private var dismiss

    // Snapshot of original state for change detection
    @State private var originalCategories: [Category] = []

    @State private var editingCategoryId: UUID? = nil
    @State private var editingCategoryName: String = ""
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var showMergeConfirmation = false
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var pendingRenames: [UUID: String] = [:]
    @State private var pendingDeletions: Set<UUID> = []
    @State private var pendingMerges: [(target: UUID, sources: Set<UUID>)] = []
    @State private var localCategories: [Category] = []
    @FocusState private var focusedRenameId: UUID?
    @FocusState private var isNewCategoryFocused: Bool

    private var displayedCategories: [Category] {
        localCategories.filter { !pendingDeletions.contains($0.id) }
    }

    private var hasChanges: Bool {
        !pendingRenames.isEmpty
        || !pendingDeletions.isEmpty
        || !pendingMerges.isEmpty
        || localCategories.map(\.id) != originalCategories.map(\.id)
        || localCategories.count != originalCategories.count
    }

    var body: some View {
        DrawerContainer(
            title: "Edit Categories",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                commitRenameIfNeeded()
                saveAllChanges()
            }, highlighted: hasChanges)
        ) {
            List {
                // Category rows
                SwiftUI.Section {
                    if displayedCategories.isEmpty {
                        Text("No categories yet")
                            .font(.sf(.body))
                            .foregroundColor(.secondary)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                    } else {
                        ForEach(displayedCategories) { category in
                            categoryRow(category: category)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                        .onMove { from, to in
                            commitRenameIfNeeded()
                            let displayedIds = displayedCategories.map(\.id)
                            var allIds = localCategories.map(\.id)
                            var reordered = displayedIds
                            reordered.move(fromOffsets: from, toOffset: to)
                            var reorderedIndex = 0
                            for i in allIds.indices {
                                if !pendingDeletions.contains(allIds[i]) {
                                    allIds[i] = reordered[reorderedIndex]
                                    reorderedIndex += 1
                                }
                            }
                            let catMap = Dictionary(uniqueKeysWithValues: localCategories.map { ($0.id, $0) })
                            localCategories = allIds.compactMap { catMap[$0] }
                        }
                    }
                }

                // Action row: [+ New Category] ... [Merge] [Trash]
                SwiftUI.Section {
                    actionRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .onAppear {
                localCategories = viewModel.categories
                originalCategories = viewModel.categories
            }
            .onChange(of: viewModel.categories.count) { _, _ in
                let localIds = Set(localCategories.map(\.id))
                for cat in viewModel.categories where !localIds.contains(cat.id) {
                    localCategories.append(cat)
                }
            }
            .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    pendingDeletions.formUnion(selectedCategoryIds)
                    selectedCategoryIds = []
                }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .alert(mergeConfirmationTitle, isPresented: $showMergeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Merge", role: .destructive) {
                    let ids = selectedCategoryIds
                    let sorted = localCategories
                        .filter { ids.contains($0.id) }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    if let target = sorted.first {
                        let sources = Set(sorted.dropFirst().map(\.id))
                        pendingMerges.append((target: target.id, sources: sources))
                        pendingDeletions.formUnion(sources)
                    }
                    selectedCategoryIds = []
                }
            } message: {
                Text(mergeConfirmationMessage)
            }
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(category: Category) -> some View {
        HStack(spacing: 10) {
            // Dotted selection circle
            Button {
                if selectedCategoryIds.contains(category.id) {
                    selectedCategoryIds.remove(category.id)
                } else {
                    commitRenameIfNeeded()
                    selectedCategoryIds.insert(category.id)
                }
            } label: {
                Image(systemName: selectedCategoryIds.contains(category.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.sf(.title3))
                    .foregroundColor(selectedCategoryIds.contains(category.id) ? .appRed : .secondary)
            }
            .buttonStyle(.plain)

            // Name (editable on tap)
            if editingCategoryId == category.id {
                TextField("Category name", text: $editingCategoryName)
                    .font(.sf(.body))
                    .focused($focusedRenameId, equals: category.id)
                    .onSubmit {
                        commitRename(for: category.id)
                    }
            } else {
                let displayName = pendingRenames[category.id] ?? category.name
                Text(displayName)
                    .font(.sf(.body))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        commitRenameIfNeeded()
                        editingCategoryId = category.id
                        editingCategoryName = pendingRenames[category.id] ?? category.name
                        focusedRenameId = category.id
                    }
            }
        }
    }

    // MARK: - Action Row (New Category + Merge + Delete)

    @ViewBuilder
    private var actionRow: some View {
        let hasSelection = !selectedCategoryIds.isEmpty
        let canMerge = selectedCategoryIds.count >= 2

        if isAddingCategory {
            HStack(spacing: 8) {
                TextField("Category name", text: $newCategoryName)
                    .font(.sf(.body))
                    .focused($isNewCategoryFocused)
                    .onSubmit { submitNewCategory() }

                Button {
                    submitNewCategory()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.sf(.subheadline, weight: .semibold))
                        .foregroundColor(
                            newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .secondary : .white
                        )
                        .frame(width: 30, height: 30)
                        .background(
                            newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(.systemGray4) : Color.appRed,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    isAddingCategory = false
                    newCategoryName = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.sf(.subheadline, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemGray4), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 8) {
                // + New Category pill
                Button {
                    commitRenameIfNeeded()
                    isAddingCategory = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewCategoryFocused = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.sf(.subheadline))
                        Text("New Category")
                            .font(.sf(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer()

                // Merge pill
                Button {
                    if canMerge {
                        showMergeConfirmation = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.sf(.subheadline))
                        Text("Merge")
                            .font(.sf(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(canMerge ? .primary : .secondary.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!canMerge)

                // Delete round button
                Button {
                    if hasSelection {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(hasSelection ? .red : .secondary.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!hasSelection)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func commitRename(for categoryId: UUID) {
        let trimmed = editingCategoryName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let original = viewModel.categories.first(where: { $0.id == categoryId })
            if trimmed != original?.name {
                pendingRenames[categoryId] = trimmed
            } else {
                pendingRenames.removeValue(forKey: categoryId)
            }
        }
        editingCategoryId = nil
        editingCategoryName = ""
    }

    private func commitRenameIfNeeded() {
        if let id = editingCategoryId {
            commitRename(for: id)
        }
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.createCategory(name: name)
        }
        newCategoryName = ""
        isAddingCategory = false
    }

    private func saveAllChanges() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        _Concurrency.Task { @MainActor in
            // Apply renames
            for (id, newName) in pendingRenames {
                await viewModel.renameCategory(id: id, newName: newName)
            }

            // Apply merges
            for merge in pendingMerges {
                var allIds = merge.sources
                allIds.insert(merge.target)
                await viewModel.mergeCategories(ids: allIds)
            }

            // Apply deletions (skip those already deleted by merge)
            let mergedSources = Set(pendingMerges.flatMap(\.sources))
            let pureDeletions = pendingDeletions.subtracting(mergedSources)
            if !pureDeletions.isEmpty {
                await viewModel.deleteCategories(ids: pureDeletions)
            }

            // Persist reorder if order changed
            let currentIds = localCategories.map(\.id)
            let originalIds = originalCategories.map(\.id)
            if currentIds != originalIds {
                let reorderedIds = localCategories
                    .filter { !pendingDeletions.contains($0.id) }
                    .map(\.id)
                for (newIndex, id) in reorderedIds.enumerated() {
                    if let currentIndex = viewModel.categories.firstIndex(where: { $0.id == id }),
                       currentIndex != newIndex {
                        await viewModel.reorderCategories(
                            fromOffsets: IndexSet(integer: currentIndex),
                            toOffset: newIndex > currentIndex ? newIndex + 1 : newIndex
                        )
                    }
                }
            }

            dismiss()
        }
    }

    // MARK: - Confirmation Text

    private var selectedCategoryNames: [String] {
        localCategories
            .filter { selectedCategoryIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { pendingRenames[$0.id] ?? $0.name }
    }

    private func formatNameList(_ names: [String]) -> String {
        let quoted = names.map { "\"\($0)\"" }
        switch quoted.count {
        case 0: return ""
        case 1: return quoted[0]
        case 2: return "\(quoted[0]) and \(quoted[1])"
        default:
            let last = quoted.last ?? ""
            let rest = quoted.dropLast().joined(separator: ", ")
            return "\(rest), and \(last)"
        }
    }

    private var deleteConfirmationTitle: String {
        let names = selectedCategoryNames
        if names.count == 1, let name = names.first {
            return "Delete \"\(name)\"?"
        }
        return "Delete \(names.count) categories?"
    }

    private var deleteConfirmationMessage: String {
        let names = selectedCategoryNames
        guard !names.isEmpty else { return "" }
        return "Items in \(formatNameList(names)) will become uncategorized."
    }

    private var mergeConfirmationTitle: String {
        let names = selectedCategoryNames
        guard let targetName = names.first else { return "Merge?" }
        return "Merge into \"\(targetName)\"?"
    }

    private var mergeConfirmationMessage: String {
        let names = selectedCategoryNames
        guard let targetName = names.first else { return "" }
        let sourceNames = Array(names.dropFirst())
        guard !sourceNames.isEmpty else { return "" }
        return "All items from \(formatNameList(sourceNames)) will be moved to \"\(targetName)\"."
    }
}
