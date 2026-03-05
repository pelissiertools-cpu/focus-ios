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
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // List title — editable inline
                    TextField("List name", text: $listTitle, axis: .vertical)
                        .font(.inter(.title2, weight: .bold))
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit { saveListTitle() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    // Notes
                    if isNotesFocused || listNotes.isEmpty {
                        TextField("Notes", text: $listNotes, axis: .vertical)
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .textFieldStyle(.plain)
                            .focused($isNotesFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    } else {
                        Text(linkifiedText(listNotes))
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .tint(.blue.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isNotesFocused = true
                            }
                    }

                    // Items list
                    contentList
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            })
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
                }
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
            CommitmentSelectionSheet(task: item, focusViewModel: focusViewModel)
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

    @ViewBuilder
    private var contentList: some View {
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
        } else if allEmpty {
            Text("No items yet")
                .font(.inter(.headline))
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            InlineAddRow(
                placeholder: "Item title",
                buttonLabel: "Add item",
                onSubmit: { title in await viewModel.createItem(title: title, listId: list.id) },
                isAnyAddFieldActive: $isInlineAddFocused,
                verticalPadding: 8
            )
            .padding(.horizontal, 20)
        } else {
            let items = flattenedDisplayItems()

            List {
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
                            onToggle: { viewModel.toggleDoneSectionCollapsed(for: list.id) }
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
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .keyboardDismissOverlay(isActive: $isInlineAddFocused)
            .frame(minHeight: items.reduce(CGFloat(0)) { sum, item in
                switch item {
                case .item: return sum + 56
                case .addItemRow: return sum + 56
                case .completedHeader: return sum + 52
                }
            } + 20)
        }
    }
}

// MARK: - List Content Item Row

private struct ListContentItemRow: View {
    let item: FocusTask
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.inter(.body))
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task {
                    await viewModel.toggleItemCompletion(item, listId: listId)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(item.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isCompleted {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
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
    }
}

// MARK: - List Content Done Pill

private struct ListContentDonePill: View {
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

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
                        .font(.inter(size: 8, weight: .semiBold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .clipShape(Capsule())
                .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}
