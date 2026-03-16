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
    @State private var activeAddRowId: String?
    @State private var scrollToAddTrigger = 0
    @State private var listTitle: String
    @State private var listNotes: String
    @State private var editingSectionId: UUID?
    @State private var scrollToSectionId: UUID?
    @State private var showManageSharing = false
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
            Color.appBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                List {
                    // List title — editable inline
                    HStack(spacing: 8) {
                        TextField("List name", text: $listTitle, axis: .vertical)
                            .font(.inter(.title2, weight: .bold))
                            .foregroundColor(.primary)
                            .textFieldStyle(.plain)
                            .focused($isTitleFocused)
                            .onSubmit { saveListTitle() }

                        if viewModel.sharedTaskIds.contains(list.id) {
                            Image(systemName: "person.2.fill")
                                .font(.inter(.subheadline))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                    // Item count
                    let totalItems = (viewModel.itemsMap[list.id] ?? []).filter { !$0.isSection }.count
                    if totalItems > 0 {
                        Text("\(totalItems) item\(totalItems == 1 ? "" : "s")")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.tiny, trailing: AppStyle.Spacing.page))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)
                    }

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
                    .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.comfortable, trailing: AppStyle.Spacing.page))
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
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                    } else if allEmpty {
                        Text("No items yet")
                            .font(AppStyle.Typography.emptyTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)

                        InlineAddRow(
                            placeholder: "Item title",
                            buttonLabel: "Add item",
                            onSubmit: { title in
                                await viewModel.createItem(title: title, listId: list.id)
                                scrollToAddTrigger += 1
                            },
                            isAnyAddFieldActive: Binding(
                                get: { isInlineAddFocused },
                                set: { newValue in
                                    isInlineAddFocused = newValue
                                    if newValue { activeAddRowId = "inline-add-empty" }
                                }
                            ),
                            verticalPadding: AppStyle.Spacing.compact
                        )
                        .id("inline-add-empty")
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                    } else {
                        let items = viewModel.flattenedListContentItems(for: list.id)
                        let hasRealItems = items.contains { if case .item = $0 { return true }; return false }

                        if !hasRealItems {
                            Text("No items yet")
                                .font(AppStyle.Typography.emptyTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .moveDisabled(true)
                        }

                        ForEach(items) { displayItem in
                            switch displayItem {
                            case .section(let section):
                                ListSectionRow(
                                    section: section,
                                    viewModel: viewModel,
                                    listId: list.id,
                                    editingSectionId: $editingSectionId
                                )
                                .id(section.id)
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .item(let item):
                                ListContentItemRow(
                                    item: item,
                                    listId: list.id,
                                    viewModel: viewModel
                                )
                                .moveDisabled(item.isCompleted || viewModel.contentEditMode)
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .addItemRow(let sectionId):
                                if !viewModel.contentEditMode {
                                    let rowId = displayItem.id
                                    InlineAddRow(
                                        placeholder: "Item title",
                                        buttonLabel: "Add item",
                                        onSubmit: { title in
                                        await viewModel.createItemInSection(title: title, listId: list.id, sectionId: sectionId)
                                        scrollToAddTrigger += 1
                                    },
                                        isAnyAddFieldActive: Binding(
                                            get: { isInlineAddFocused },
                                            set: { newValue in
                                                isInlineAddFocused = newValue
                                                if newValue { activeAddRowId = rowId }
                                            }
                                        ),
                                        verticalPadding: AppStyle.Spacing.compact
                                    )
                                    .moveDisabled(true)
                                    .listRowInsets(AppStyle.Insets.row)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }

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
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .onMove { from, to in
                            if !viewModel.contentEditMode {
                                viewModel.handleListContentFlatMove(from: from, to: to, listId: list.id)
                            }
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
                        .frame(height: 500)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: isInlineAddFocused) { _, focused in
                    if focused, let targetId = activeAddRowId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.5))
                            }
                        }
                    }
                }
                .onChange(of: scrollToAddTrigger) { _, _ in
                    guard isInlineAddFocused, let targetId = activeAddRowId else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.5))
                        }
                    }
                }
                .onChange(of: scrollToSectionId) { _, newId in
                    if let sectionId = newId {
                        scrollToSectionId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(sectionId, anchor: UnitPoint(x: 0.5, y: 0.75))
                            }
                        }
                    }
                }
            }

            // Edit mode action bar
            if viewModel.contentEditMode {
                ListContentEditModeActionBar(viewModel: viewModel, listId: list.id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.contentEditMode {
                    Button {
                        viewModel.exitContentEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.focusBlue)
                    }
                } else {
                    Button {
                        saveListTitle()
                        saveListNotes()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                Text("List")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.secondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.contentEditMode {
                    Button {
                        if viewModel.allContentItemsSelected(for: list.id) {
                            viewModel.deselectAllContentItems()
                        } else {
                            viewModel.selectAllContentItems(listId: list.id)
                        }
                    } label: {
                        Text(viewModel.allContentItemsSelected(for: list.id) ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.focusBlue)
                    }
                } else {
                    Menu {
                        Button {
                            viewModel.enterContentEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }

                        Button {
                            _Concurrency.Task {
                                await viewModel.createListSection(
                                    title: "",
                                    listId: list.id
                                )
                                if let items = viewModel.itemsMap[list.id],
                                   let newSection = items.last(where: { $0.isSection }) {
                                    editingSectionId = newSection.id
                                    scrollToSectionId = newSection.id
                                }
                            }
                        } label: {
                            Label("Add section", systemImage: "plus")
                        }

                        Button {
                            ShareSheetHelper.share(task: list)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        if viewModel.sharedTaskIds.contains(list.id) {
                            Button {
                                showManageSharing = true
                            } label: {
                                Label("Manage Sharing", systemImage: "person.2")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
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
            if viewModel.contentEditMode {
                viewModel.exitContentEditMode()
            }
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
        .sheet(isPresented: $showManageSharing) {
            ManageSharingSheet(task: list)
                .drawerStyle()
        }
        // Batch delete confirmation
        .alert("Delete \(viewModel.selectedContentItemIds.count) item\(viewModel.selectedContentItemIds.count == 1 ? "" : "s")?",
               isPresented: $viewModel.showContentBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.batchDeleteContentItems(listId: list.id)
                }
            }
        } message: {
            Text("This will permanently delete the selected items and their schedules.")
        }
        // Batch move sheet
        .sheet(isPresented: $viewModel.showContentBatchMovePicker) {
            ContentBatchMoveSheet(source: .list(id: list.id, viewModel: viewModel))
                .drawerStyle()
        }
        // Batch schedule sheet
        .sheet(isPresented: $viewModel.showContentBatchScheduleSheet) {
            BatchScheduleSheet(
                viewModel: viewModel,
                tasks: (viewModel.itemsMap[list.id] ?? []).filter { viewModel.selectedContentItemIds.contains($0.id) },
                onComplete: { viewModel.exitContentEditMode() }
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

}

// MARK: - List Section Row

struct ListSectionRow: View {
    let section: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    let listId: UUID
    @Binding var editingSectionId: UUID?
    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(section: FocusTask, viewModel: ListsViewModel, listId: UUID, editingSectionId: Binding<UUID?>) {
        self.section = section
        self.viewModel = viewModel
        self.listId = listId
        self._editingSectionId = editingSectionId
        _sectionTitle = State(initialValue: section.title)
    }

    private var itemCount: Int {
        viewModel.sectionItemCount(sectionId: section.id, listId: listId)
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

                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.inter(.caption, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, AppStyle.Spacing.section)

            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
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
                    await viewModel.deleteListSection(section, listId: listId)
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
        .onChange(of: section.title) { _, newTitle in
            if !isEditing { sectionTitle = newTitle }
        }
    }

    private func saveSectionTitle() {
        let trimmed = sectionTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await viewModel.renameListSection(section, newTitle: trimmed)
        }
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
    private var isScheduled: Bool { viewModel.scheduledTaskIds.contains(item.id) }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if viewModel.contentEditMode {
                Image(systemName: viewModel.selectedContentItemIds.contains(item.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedContentItemIds.contains(item.id) ? .appRed : .secondary)
                    .accessibilityLabel(viewModel.selectedContentItemIds.contains(item.id) ? "Selected" : "Select")
            }

            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(item.title)
                    .font(AppStyle.Typography.itemTitle)
                    .strikethrough(displayCompleted)
                    .foregroundColor(displayCompleted ? .secondary : .primary)

                if isScheduled {
                    Image(systemName: "calendar")
                        .font(.inter(.caption2))
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.iconButton, alignment: .leading)

            if !viewModel.contentEditMode {
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
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.contentEditMode {
                if !item.isCompleted {
                    viewModel.toggleContentItemSelection(item.id)
                }
            } else {
                viewModel.selectedItemForDetails = item
            }
        }
        .contextMenu {
            if !viewModel.contentEditMode && !item.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedItemForDetails = item
                }

                ContextMenuItems.scheduleButton {
                    viewModel.selectedItemForSchedule = item
                }

                if isScheduled {
                    ContextMenuItems.unscheduleButton {
                        _Concurrency.Task {
                            try? await ScheduleRepository().deleteSchedules(forTask: item.id)
                            await viewModel.fetchScheduledTaskIds()
                        }
                    }
                }

                ContextMenuItems.pinButton(isPinned: item.isPinned) {
                    _Concurrency.Task { await viewModel.togglePin(item, listId: listId) }
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
            if !viewModel.contentEditMode && !item.isCompleted {
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

// MARK: - List Content Edit Mode Action Bar

struct ListContentEditModeActionBar: View {
    @ObservedObject var viewModel: ListsViewModel
    let listId: UUID

    private var hasSelection: Bool { !viewModel.selectedContentItemIds.isEmpty }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isDestructive: Bool
        let action: () -> Void
    }

    private var actions: [ActionItem] {
        [
            ActionItem(icon: "trash", label: "Delete", isDestructive: true) {
                viewModel.showContentBatchDeleteConfirmation = true
            },
            ActionItem(icon: "arrow.right", label: "Move", isDestructive: false) {
                viewModel.showContentBatchMovePicker = true
            },
            ActionItem(icon: "calendar", label: "Schedule", isDestructive: false) {
                viewModel.showContentBatchScheduleSheet = true
            },
        ]
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()

                HStack(alignment: .top, spacing: AppStyle.Spacing.content) {
                    // Floating labels
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { _, item in
                            Text(LocalizedStringKey(item.label))
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                                .frame(height: AppStyle.Layout.largeButton)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasSelection { item.action() }
                                }
                        }
                    }

                    // Vertical glass capsule with icons
                    VStack(spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { index, item in
                            Button {
                                item.action()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.inter(.title3))
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                    .frame(width: AppStyle.Layout.largeButton, height: AppStyle.Layout.largeButton)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasSelection)

                            if index < actions.count - 1 {
                                Divider()
                                    .frame(width: 28)
                            }
                        }
                    }
                    .padding(.vertical, AppStyle.Spacing.small)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(radius: 4, y: 2)
                }
                .opacity(hasSelection ? 1.0 : 0.5)
                .padding(.trailing, AppStyle.Spacing.page)
                .padding(.top, 62)
            }
            Spacer()
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
        HStack(spacing: AppStyle.Spacing.compact) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
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
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)
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
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.small)
                    .clipShape(Capsule())
                    .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppStyle.Spacing.medium)
    }
}
