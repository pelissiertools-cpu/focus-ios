//
//  ListContentView.swift
//  Focus IOS
//

import SwiftUI

struct ListContentView: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var listTitle: String
    @State private var listNotes: String
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool

    init(list: FocusTask, viewModel: ListsViewModel) {
        self.list = list
        self.viewModel = viewModel
        _listTitle = State(initialValue: list.title)
        _listNotes = State(initialValue: list.description ?? "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // List title — editable inline
                TextField("List name", text: $listTitle, axis: .vertical)
                    .font(.inter(.title2, weight: .bold))
                    .foregroundColor(.primary)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onSubmit { saveListTitle() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                // Notes
                Group {
                    if isNotesFocused || listNotes.isEmpty {
                        TextField("Notes", text: $listNotes, axis: .vertical)
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .textFieldStyle(.plain)
                            .focused($isNotesFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(linkifiedText(listNotes))
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .tint(.blue.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isNotesFocused = true
                            }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .moveDisabled(true)

                // Content
                let uncompletedItems = viewModel.getUncompletedItems(for: list.id)
                let completedItems = viewModel.getCompletedItems(for: list.id)
                let allEmpty = uncompletedItems.isEmpty && completedItems.isEmpty

                if allEmpty && viewModel.isLoadingItems.contains(list.id) {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .padding()
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                } else if allEmpty {
                    Text("No items yet")
                        .font(AppStyle.Typography.emptyTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                    InlineAddRow(
                        placeholder: "Item title",
                        buttonLabel: "Add item",
                        onSubmit: { title in await viewModel.createItem(title: title, listId: list.id) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 8
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                } else {
                    let items = flattenedDisplayItems()

                    ForEach(items) { displayItem in
                        switch displayItem {
                        case .item(let item):
                            ListContentItemRow(
                                item: item,
                                listId: list.id,
                                viewModel: viewModel
                            )
                            .moveDisabled(item.isCompleted)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .addItemRow:
                            InlineAddRow(
                                placeholder: "Item title",
                                buttonLabel: "Add item",
                                onSubmit: { title in await viewModel.createItem(title: title, listId: list.id) },
                                isAnyAddFieldActive: $isInlineAddFocused,
                                verticalPadding: 8
                            )
                            .moveDisabled(true)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .completedHeader(let count):
                            ListContentDonePill(
                                count: count,
                                isCollapsed: viewModel.isDoneSectionCollapsed(for: list.id),
                                onToggle: { viewModel.toggleDoneSectionCollapsed(for: list.id) },
                                onClear: {
                                    _Concurrency.Task {
                                        await viewModel.clearCompletedItems(for: list.id)
                                    }
                                }
                            )
                            .moveDisabled(true)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.handleListContentFlatMove(from: from, to: to, listId: list.id)
                    }
                }

                Color.clear
                    .frame(height: 1)
                    .id("inline-add-anchor")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                Color.clear
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: isInlineAddFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("inline-add-anchor", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    saveListTitle()
                    saveListNotes()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }
        }
        .task {
            await viewModel.fetchItems(for: list.id)
            viewModel.expandedLists.insert(list.id)
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused { saveListTitle() }
        }
        .onChange(of: isNotesFocused) { _, focused in
            if !focused { saveListNotes() }
        }
        .onDisappear {
            saveListNotes()
        }
        // Item edit drawer
        .sheet(item: $viewModel.selectedItemForDetails) { item in
            TaskDetailsDrawer(task: item, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
        }
        // Item schedule sheet
        .sheet(item: $viewModel.selectedItemForSchedule) { item in
            ScheduleSelectionSheet(
                task: item,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
    }

    private func saveListTitle() {
        let trimmed = listTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != list.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(list, newTitle: trimmed)
        }
    }

    private func saveListNotes() {
        let newNote = listNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = list.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard newNote != current else { return }
        _Concurrency.Task {
            await viewModel.updateTaskNote(list, newNote: newNote.isEmpty ? nil : newNote)
        }
    }

    private func linkifiedText(_ string: String) -> AttributedString {
        var result = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        for match in detector.matches(in: string, range: nsRange) {
            guard let url = match.url,
                  let range = Range(match.range, in: string) else { continue }
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].link = url
            }
        }
        return result
    }

    // MARK: - Content List

    private enum ListDisplayItem: Identifiable {
        case item(FocusTask)
        case addItemRow
        case completedHeader(count: Int)

        var id: String {
            switch self {
            case .item(let task): return task.id.uuidString
            case .addItemRow: return "add-item-row"
            case .completedHeader: return "completed-header"
            }
        }
    }

    private func flattenedDisplayItems() -> [ListDisplayItem] {
        let uncompleted = viewModel.getUncompletedItems(for: list.id)
        let completed = viewModel.getCompletedItems(for: list.id)

        var result: [ListDisplayItem] = []

        for item in uncompleted {
            result.append(.item(item))
        }

        result.append(.addItemRow)

        if !completed.isEmpty {
            result.append(.completedHeader(count: completed.count))

            if !viewModel.isDoneSectionCollapsed(for: list.id) {
                for item in completed {
                    result.append(.item(item))
                }
            }
        }

        return result
    }

}

// MARK: - List Content Item Row

private struct ListContentItemRow: View {
    let item: FocusTask
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @State private var showDeleteConfirmation = false

    private var isPending: Bool { viewModel.isPendingCompletion(item.id) }
    private var displayCompleted: Bool { item.isCompleted || isPending }

    var body: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(AppStyle.Typography.itemTitle)
                .strikethrough(displayCompleted)
                .foregroundColor(displayCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                viewModel.requestToggleItemCompletion(item, listId: listId)
            } label: {
                Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(displayCompleted ? Color.focusBlue.opacity(0.6) : .gray)
                    .symbolEffect(.pulse, isActive: isPending)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayCompleted ? "Completed" : "Mark complete")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemForDetails = item
        }
        .contextMenu {
            if !item.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedItemForDetails = item
                }

                ContextMenuItems.scheduleButton {
                    viewModel.selectedItemForSchedule = item
                }

                Divider()

                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteItem(item, listId: listId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isCompleted {
                Button(role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteItem(item, listId: listId)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - List Content Done Pill

private struct ListContentDonePill: View {
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Completed")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("\(count)")
                        .font(.inter(size: 12))
                        .foregroundColor(.secondary)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(AppStyle.Typography.chevron)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .clipShape(Capsule())
                .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onClear()
            } label: {
                Text("Clear")
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .clipShape(Capsule())
                    .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}
