//
//  ListsView.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Lists View

struct ListsView: View {
    @ObservedObject var viewModel: ListsViewModel
    let searchText: String

    // Drag state
    @State private var draggingListId: UUID?
    @State private var draggingItemId: UUID?
    @State private var draggingItemListId: UUID?
    @State private var dragFingerY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var dragReorderAdjustment: CGFloat = 0
    @State private var lastReorderTime: Date = .distantPast
    @State private var rowFrames: [UUID: CGRect] = [:]

    init(viewModel: ListsViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading lists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.lists.isEmpty {
                emptyState
            } else if viewModel.filteredLists.isEmpty {
                VStack(spacing: 12) {
                    Text("No matching lists")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                listContent
            }
        }
        .padding(.top, 44)
        .sheet(isPresented: $viewModel.showingAddList) {
            AddListSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: viewModel)
                .drawerStyle()
        }
        .sheet(item: $viewModel.selectedItemForDetails) { item in
            TaskDetailsDrawer(task: item, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        // Batch delete confirmation
        .alert("Delete \(viewModel.selectedCount) list\(viewModel.selectedCount == 1 ? "" : "s")?", isPresented: $viewModel.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.batchDeleteLists() }
            }
        } message: {
            Text("This will permanently delete the selected lists and all their items.")
        }
        // Batch move category sheet
        .sheet(isPresented: $viewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: viewModel)
                .drawerStyle()
        }
        // Batch commit sheet
        .sheet(isPresented: $viewModel.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: viewModel)
                .drawerStyle()
        }
        .task {
            if viewModel.lists.isEmpty && !viewModel.isLoading {
                await viewModel.fetchLists()
            }
        }
        .onAppear {
            viewModel.searchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Lists Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to create your first list")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.filteredLists.enumerated()), id: \.element.id) { index, list in
                    let isDragging = draggingListId == list.id

                    VStack(spacing: 0) {
                        if index > 0 {
                            Divider()
                        }

                        // List header row (NOT checkable)
                        ListRow(
                            list: list,
                            viewModel: viewModel,
                            onDragChanged: viewModel.isEditMode ? nil : { value in handleListDrag(list.id, value) },
                            onDragEnded: viewModel.isEditMode ? nil : { handleListDragEnd() },
                            isEditMode: viewModel.isEditMode,
                            isSelected: viewModel.selectedListIds.contains(list.id),
                            onSelectToggle: { viewModel.toggleListSelection(list.id) }
                        )

                        // Expanded content: items + done section + add row
                        if !viewModel.isEditMode && viewModel.isExpanded(list.id) {
                            ListItemsSection(
                                list: list,
                                viewModel: viewModel,
                                draggingItemId: draggingItemId,
                                dragTranslation: dragTranslation,
                                dragReorderAdjustment: dragReorderAdjustment,
                                dragFingerY: dragFingerY,
                                rowFrames: rowFrames,
                                onItemDragChanged: { itemId, value in
                                    handleItemDrag(itemId, listId: list.id, value)
                                },
                                onItemDragEnded: { handleItemDragEnd() }
                            )

                            // Done section within this list
                            ListDoneSection(listId: list.id, viewModel: viewModel)

                            // Inline add item row
                            InlineAddItemRow(listId: list.id, viewModel: viewModel)
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowFramePreference.self,
                                value: [list.id: geo.frame(in: .named("listsList"))]
                            )
                        }
                    )
                    .background(Color(.systemBackground))
                    .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                    .scaleEffect(isDragging ? 1.03 : 1.0)
                    .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                    .zIndex(isDragging ? 1 : 0)
                    .transaction { t in
                        if isDragging { t.animation = nil }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
            .onPreferenceChange(RowFramePreference.self) { frames in
                rowFrames = frames
            }
        }
        .coordinateSpace(name: "listsList")
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchLists()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - List Drag Handlers

    private func handleListDrag(_ listId: UUID, _ value: DragGesture.Value) {
        guard draggingItemId == nil else { return }

        if draggingListId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingListId = listId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        let filtered = viewModel.filteredLists
        guard let currentIdx = filtered.firstIndex(where: { $0.id == listId }) else { return }

        for (idx, other) in filtered.enumerated() where other.id != listId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderList(droppedId: listId, targetId: other.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleListDragEnd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingListId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
        }
        lastReorderTime = .distantPast
    }

    // MARK: - Item Drag Handlers

    private func handleItemDrag(_ itemId: UUID, listId: UUID, _ value: DragGesture.Value) {
        guard draggingListId == nil else { return }

        if draggingItemId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingItemId = itemId
                draggingItemListId = listId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        let uncompleted = viewModel.getUncompletedItems(for: listId)
        guard let currentIdx = uncompleted.firstIndex(where: { $0.id == itemId }) else { return }

        for (idx, other) in uncompleted.enumerated() where other.id != itemId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderItem(droppedId: itemId, targetId: other.id, listId: listId)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleItemDragEnd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingItemId = nil
            draggingItemListId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
        }
        lastReorderTime = .distantPast
    }
}

// MARK: - List Row (NO checkbox — lists are not checkable)

struct ListRow: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: (() -> Void)? = nil

    private var itemCount: (uncompleted: Int, total: Int) {
        let items = viewModel.itemsMap[list.id] ?? []
        let completed = items.filter { $0.isCompleted }.count
        return (items.count - completed, items.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Edit mode: selection circle
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            } else if onDragChanged != nil {
                // Drag handle
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("listsList"))
                            .onChanged { value in onDragChanged?(value) }
                            .onEnded { _ in onDragEnded?() }
                    )
            }

            // Title + item count
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.headline)
                    .lineLimit(1)

                if itemCount.total > 0 {
                    Text("\(itemCount.uncompleted) item\(itemCount.uncompleted == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onSelectToggle?()
            } else {
                _Concurrency.Task {
                    await viewModel.toggleExpanded(list.id)
                }
            }
        }
        .onLongPressGesture {
            if !isEditMode {
                viewModel.selectedListForDetails = list
            }
        }
    }
}

// MARK: - List Items Section (uncompleted items with drag-to-reorder)

struct ListItemsSection: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    var draggingItemId: UUID? = nil
    var dragTranslation: CGFloat = 0
    var dragReorderAdjustment: CGFloat = 0
    var dragFingerY: CGFloat = 0
    var rowFrames: [UUID: CGRect] = [:]
    var onItemDragChanged: ((UUID, DragGesture.Value) -> Void)? = nil
    var onItemDragEnded: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.getUncompletedItems(for: list.id)) { item in
                let isDragging = draggingItemId == item.id

                ListItemRow(
                    item: item,
                    listId: list.id,
                    viewModel: viewModel,
                    onDragChanged: onItemDragChanged != nil
                        ? { value in onItemDragChanged?(item.id, value) }
                        : nil,
                    onDragEnded: onItemDragEnded
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RowFramePreference.self,
                            value: [item.id: geo.frame(in: .named("listsList"))]
                        )
                    }
                )
                .background(Color(.systemBackground))
                .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                .scaleEffect(isDragging ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                .zIndex(isDragging ? 1 : 0)
                .transaction { t in
                    if isDragging { t.animation = nil }
                }
            }
        }
        .padding(.leading, 32)
    }
}

// MARK: - List Item Row (WITH checkbox)

struct ListItemRow: View {
    let item: FocusTask
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.subheadline)
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox
            Button {
                _Concurrency.Task {
                    await viewModel.toggleItemCompletion(item, listId: listId)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemForDetails = item
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("listsList")))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if let drag = drag {
                            onDragChanged?(drag)
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    onDragEnded?()
                },
            isEnabled: !item.isCompleted && onDragChanged != nil
        )
    }
}

// MARK: - List Done Section (per-list collapsible done with "Clear list")

struct ListDoneSection: View {
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @State private var showClearConfirmation = false

    private var completedItems: [FocusTask] {
        viewModel.getCompletedItems(for: listId)
    }

    private var isExpanded: Bool {
        !viewModel.isDoneSectionCollapsed(for: listId)
    }

    var body: some View {
        if !completedItems.isEmpty {
            VStack(spacing: 0) {
                // Done pill header
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleDoneSectionCollapsed(for: listId)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Completed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text("(\(completedItems.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if isExpanded {
                            Button {
                                showClearConfirmation = true
                            } label: {
                                Text("Clear list")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded completed items
                if isExpanded {
                    ForEach(completedItems) { item in
                        VStack(spacing: 0) {
                            Divider()
                            ListItemRow(item: item, listId: listId, viewModel: viewModel)
                        }
                    }
                }
            }
            .padding(.leading, 32)
            .alert("Clear completed items?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.clearCompletedItems(for: listId)
                    }
                }
            } message: {
                Text("This will permanently delete \(completedItems.count) completed item\(completedItems.count == 1 ? "" : "s").")
            }
        }
    }
}

// MARK: - Inline Add Item Row

struct InlineAddItemRow: View {
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @State private var newItemTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Item title", text: $newItemTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitItem()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline)
                        Text("Add")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 32)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                isEditing = false
                newItemTitle = ""
            }
        }
    }

    private func submitItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        _Concurrency.Task {
            await viewModel.createItem(title: title, listId: listId)
            newItemTitle = ""
            isFocused = true
        }
    }
}

// MARK: - Add List Sheet

struct AddListSheet: View {
    @ObservedObject var viewModel: ListsViewModel
    @State private var listTitle = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var draftItems: [DraftSubtaskEntry] = []
    @State private var commitAfterCreate = false
    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .focus
    @State private var selectedDates: Set<Date> = []
    @State private var sheetDetent: PresentationDetent = .fraction(0.75)
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @FocusState private var titleFocused: Bool
    @FocusState private var focusedItemId: UUID?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // List title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("List Name")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        TextField("What's your list for?", text: $listTitle)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }

                    // Items
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Items")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        ForEach(draftItems) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.subheadline)
                                    .foregroundColor(.gray.opacity(0.5))

                                TextField("Item title", text: Binding(
                                    get: { draftItems.first(where: { $0.id == entry.id })?.title ?? "" },
                                    set: { newValue in
                                        if let idx = draftItems.firstIndex(where: { $0.id == entry.id }) {
                                            draftItems[idx].title = newValue
                                        }
                                    }
                                ))
                                .font(.subheadline)
                                .focused($focusedItemId, equals: entry.id)
                                .onSubmit {
                                    addNewDraftItem()
                                }

                                Button {
                                    draftItems.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            addNewDraftItem()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add item")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Category picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        HStack {
                            Picker("Category", selection: $selectedCategoryId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(viewModel.categories) { category in
                                    Text(category.name).tag(category.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button {
                                showNewCategory = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("New")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if showNewCategory {
                            HStack {
                                TextField("Category name", text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)

                                Button("Add") {
                                    submitNewCategory()
                                }
                                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // Commit to Focus toggle
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $commitAfterCreate.animation(.easeInOut(duration: 0.2))) {
                            Label("Commit to Focus", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(.blue)

                        if commitAfterCreate {
                            Picker("Section", selection: $selectedSection) {
                                Text("Focus").tag(Section.focus)
                                Text("Extra").tag(Section.extra)
                            }
                            .pickerStyle(.segmented)

                            UnifiedCalendarPicker(
                                selectedDates: $selectedDates,
                                selectedTimeframe: $selectedTimeframe
                            )
                        }
                    }

                    // Create button
                    Button {
                        createList()
                    } label: {
                        Text("Create List")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(listTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.blue.opacity(0.5) : Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(listTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                    .id("createButton")
                }
                .padding()
            }
            .onChange(of: commitAfterCreate) { _, isOn in
                if isOn {
                    titleFocused = false
                    focusedItemId = nil
                }
                withAnimation {
                    sheetDetent = isOn ? .large : .fraction(0.75)
                }
                if isOn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("createButton", anchor: .bottom)
                        }
                    }
                }
            }
            } // ScrollViewReader
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        viewModel.showingAddList = false
                    }
                }
            }
            .onAppear {
                titleFocused = true
            }
            .presentationDetents([.fraction(0.75), .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    private func createList() {
        let title = listTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let itemTitles = draftItems.map { $0.title.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        _Concurrency.Task { @MainActor in
            await viewModel.createList(title: title, categoryId: selectedCategoryId)
            // Create draft items for the newly created list
            if let createdList = viewModel.lists.last {
                for itemTitle in itemTitles {
                    await viewModel.createItem(title: itemTitle, listId: createdList.id)
                }
                // Auto-expand the new list if it has items
                if !itemTitles.isEmpty {
                    viewModel.expandedLists.insert(createdList.id)
                }

                // Create commitments if toggle is on and dates selected
                if commitAfterCreate && !selectedDates.isEmpty {
                    let commitmentRepository = CommitmentRepository()
                    for date in selectedDates {
                        let commitment = Commitment(
                            userId: createdList.userId,
                            taskId: createdList.id,
                            timeframe: selectedTimeframe,
                            section: selectedSection,
                            commitmentDate: date,
                            sortOrder: 0
                        )
                        _ = try? await commitmentRepository.createCommitment(commitment)
                    }
                    await focusViewModel.fetchCommitments()
                    await viewModel.fetchCommittedTaskIds()
                }
            }
            listTitle = ""
            draftItems = []
            viewModel.showingAddList = false
        }
    }

    private func addNewDraftItem() {
        let newEntry = DraftSubtaskEntry()
        draftItems.append(newEntry)
        focusedItemId = newEntry.id
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.createCategory(name: name)
            if let created = viewModel.categories.last {
                selectedCategoryId = created.id
            }
            newCategoryName = ""
            showNewCategory = false
        }
    }
}

// MARK: - List Details Drawer (long-press on list title)

struct ListDetailsDrawer: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    @State private var listTitle: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""
    @State private var showingCommitmentSheet = false
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss

    init(list: FocusTask, viewModel: ListsViewModel) {
        self.list = list
        self.viewModel = viewModel
        _listTitle = State(initialValue: list.title)
    }

    var body: some View {
        NavigationView {
            SwiftUI.List {
                SwiftUI.Section("Title") {
                    TextField("List title", text: $listTitle)
                        .onSubmit { saveTitle() }
                }

                SwiftUI.Section("Statistics") {
                    let items = viewModel.itemsMap[list.id] ?? []
                    let completed = items.filter { $0.isCompleted }.count
                    Label("\(completed)/\(items.count) items done", systemImage: "checklist")
                        .foregroundColor(.secondary)
                }

                SwiftUI.Section("Category") {
                    Menu {
                        Button {
                            _Concurrency.Task {
                                await viewModel.moveTaskToCategory(list, categoryId: nil)
                            }
                        } label: {
                            if list.categoryId == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }

                        ForEach(viewModel.categories) { category in
                            Button {
                                _Concurrency.Task {
                                    await viewModel.moveTaskToCategory(list, categoryId: category.id)
                                }
                            } label: {
                                if list.categoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
                            }
                        }

                        Divider()

                        Button {
                            showingNewCategory = true
                        } label: {
                            Label("New Category", systemImage: "plus")
                        }
                    } label: {
                        HStack {
                            Text("Move to")
                            Spacer()
                            Text(currentCategoryName)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                SwiftUI.Section {
                    Button {
                        showingCommitmentSheet = true
                    } label: {
                        Label("Commit to Focus", systemImage: "arrow.right.circle")
                    }
                }

                SwiftUI.Section {
                    Button(role: .destructive) {
                        _Concurrency.Task {
                            await viewModel.deleteList(list)
                            dismiss()
                        }
                    } label: {
                        Label("Delete List", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("List Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        saveTitle()
                        dismiss()
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let name = newCategoryName
                    newCategoryName = ""
                    _Concurrency.Task {
                        await viewModel.createCategoryAndMove(name: name, task: list)
                    }
                }
            }
            .sheet(isPresented: $showingCommitmentSheet, onDismiss: {
                _Concurrency.Task { await viewModel.fetchCommittedTaskIds() }
            }) {
                CommitmentSelectionSheet(task: list, focusViewModel: focusViewModel)
            }
        }
    }

    private var currentCategoryName: String {
        if let categoryId = list.categoryId,
           let category = viewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "None"
    }

    private func saveTitle() {
        let trimmed = listTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != list.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(list, newTitle: trimmed)
        }
    }
}

#Preview {
    ListsView(viewModel: ListsViewModel(authService: AuthService()))
}
