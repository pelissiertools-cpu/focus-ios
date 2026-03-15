//
//  ListDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ListDetailsDrawer: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    @State private var listTitle: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedPriority: Priority
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var noteText: String
    @State private var showingScheduleSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isItemsExpanded = false
    @State private var newItemTitle = ""
    @State private var showNewItemField = false
    @FocusState private var isNewItemFocused: Bool
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @FocusState private var isTitleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(list: FocusTask, viewModel: ListsViewModel) {
        self.list = list
        self.viewModel = viewModel
        _listTitle = State(initialValue: list.title)
        _noteText = State(initialValue: list.description ?? "")
        _selectedCategoryId = State(initialValue: list.categoryId)
        _selectedPriority = State(initialValue: list.priority)
    }

    private var hasNoteChanges: Bool {
        noteText != (list.description ?? "")
    }

    private var hasChanges: Bool {
        listTitle != list.title || selectedCategoryId != list.categoryId || selectedPriority != list.priority || hasNoteChanges
    }

    private var listItems: [FocusTask] {
        viewModel.itemsMap[list.id] ?? []
    }

    private var currentCategoryName: String {
        if let id = selectedCategoryId,
           let cat = viewModel.categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "Category"
    }

    var body: some View {
        DrawerContainer(
            title: "List Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: AppStyle.Spacing.comfortable) {
                    // ─── TITLE ───
                    titleCard

                    // ─── PILL ACTIONS ───
                    actionPillsRow

                    // ─── ITEMS ───
                    itemsCard

                    // ─── NOTE ───
                    noteCard
                }
                .padding(.bottom, AppStyle.Spacing.page)
            }
            .background(.clear)
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .sheet(isPresented: $showingScheduleSheet, onDismiss: {
                _Concurrency.Task { await viewModel.fetchScheduledTaskIds() }
            }) {
                ScheduleSelectionSheet(
                    task: list,
                    focusViewModel: focusViewModel
                )
            }
            .task {
                await viewModel.fetchItems(for: list.id)
            }
            .alert("Delete list?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteList(list)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete this list and all its items.")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("List title", text: $listTitle, axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.section)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }

    // MARK: - Action Pills Row

    @ViewBuilder
    private var actionPillsRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            // Priority pill
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        selectedPriority = priority
                    } label: {
                        if selectedPriority == priority {
                            Label(priority.displayName, systemImage: "checkmark")
                        } else {
                            Text(priority.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.small) {
                    Circle()
                        .fill(selectedPriority.dotColor)
                        .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                    Text(LocalizedStringKey(selectedPriority.displayName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            // Category pill
            Menu {
                Button {
                    selectedCategoryId = nil
                } label: {
                    if selectedCategoryId == nil {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(viewModel.categories) { category in
                    Button {
                        selectedCategoryId = category.id
                    } label: {
                        if selectedCategoryId == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
                Divider()
                Button {
                    showingNewCategoryAlert = true
                } label: {
                    Label("New Category", systemImage: "plus")
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.small) {
                    Image(systemName: "folder")
                        .font(.inter(.subheadline))
                    Text(LocalizedStringKey(currentCategoryName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            // Schedule pill
            Button {
                showingScheduleSheet = true
            } label: {
                HStack(spacing: AppStyle.Spacing.small) {
                    Image(systemName: "calendar")
                        .font(.inter(.subheadline))
                    Text("Date")
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Delete circle
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.red)
                    .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Items Card

    @ViewBuilder
    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Items" label + count + collapse toggle
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isItemsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Text("Items")
                            .font(.inter(.subheadline, weight: .medium))
                            .foregroundColor(.primary)

                        if !listItems.isEmpty {
                            Text("\(listItems.count)")
                                .font(.inter(.caption, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.inter(.caption2, weight: .semiBold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isItemsExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.comfortable)
            .padding(.bottom, AppStyle.Spacing.medium)

            if isItemsExpanded {
                VStack(spacing: AppStyle.Spacing.content) {
                    ForEach(listItems) { item in
                        compactItemRow(item)
                    }

                    // New item entry
                    if showNewItemField || !newItemTitle.isEmpty {
                        HStack(spacing: AppStyle.Spacing.compact) {
                            Image(systemName: "circle")
                                .font(.inter(.caption2))
                                .foregroundColor(.secondary.opacity(0.5))

                            TextField("Item", text: $newItemTitle)
                                .font(.inter(.body))
                                .textFieldStyle(.plain)
                                .focused($isNewItemFocused)
                                .onAppear { isNewItemFocused = true }
                                .onSubmit { addItem() }

                            Button {
                                newItemTitle = ""
                                showNewItemField = false
                                isNewItemFocused = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.inter(.caption))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // "+ Item" pill button
                    HStack {
                        Button {
                            if !newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                addItem()
                            }
                            showNewItemField = true
                            isNewItemFocused = true
                        } label: {
                            HStack(spacing: AppStyle.Spacing.tiny) {
                                Image(systemName: "plus")
                                    .font(.inter(size: 14, weight: .semiBold))
                                Text("Item")
                                    .font(.inter(size: 14, weight: .semiBold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, AppStyle.Spacing.comfortable)
                            .padding(.vertical, AppStyle.Spacing.medium)
                            .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.medium)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    @ViewBuilder
    private func compactItemRow(_ item: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.inter(.caption2))
                .foregroundColor(item.isCompleted ? Color.focusBlue.opacity(0.6) : .secondary.opacity(0.5))

            Text(item.title)
                .font(.inter(.body))
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            Spacer()

            if !item.isCompleted {
                Button {
                    _Concurrency.Task {
                        await viewModel.deleteItem(item, listId: list.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            _Concurrency.Task {
                await viewModel.toggleItemCompletion(item, listId: list.id)
            }
        }
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newItemTitle = ""
        _Concurrency.Task {
            await viewModel.createItem(title: title, listId: list.id)
        }
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.inter(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                }
                TextEditor(text: $noteText)
                    .font(.inter(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .padding(.vertical, AppStyle.Spacing.micro)
            }
            .padding(.horizontal, AppStyle.Spacing.compact)
            .padding(.bottom, AppStyle.Spacing.medium)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Actions

    private func saveTitle() {
        let trimmed = listTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != list.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(list, newTitle: trimmed)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(list, newNote: note.isEmpty ? nil : note)
        }
    }

    private func savePriority() {
        guard selectedPriority != list.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(list, priority: selectedPriority)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != list.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(list, categoryId: selectedCategoryId)
        }
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: list)
            dismiss()
        }
    }
}
