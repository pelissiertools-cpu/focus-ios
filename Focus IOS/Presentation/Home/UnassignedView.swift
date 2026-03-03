//
//  UnassignedView.swift
//  Focus IOS
//

import SwiftUI

struct UnassignedView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    /// Tasks not in a project
    private var standaloneUncompletedTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil }
    }

    /// Lists not in a project
    private var standaloneFilteredLists: [FocusTask] {
        listsVM.filteredLists.filter { $0.projectId == nil }
    }

    private var isEmpty: Bool {
        standaloneUncompletedTasks.isEmpty &&
        standaloneFilteredLists.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.inter(size: 22, weight: .regular))
                        .foregroundColor(.primary)

                    Text("Unassign")
                        .font(.inter(size: 28, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isEmpty {
                    VStack(spacing: 4) {
                        Text("No unassigned items")
                            .font(.inter(.headline))
                            .bold()
                        Text("Tasks and lists without a schedule will appear here")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else {
                    itemList
                }
            }

            // Edit mode action bar
            if taskListVM.isEditMode {
                EditModeActionBar(
                    viewModel: taskListVM,
                    showCreateProjectAlert: $showCreateProjectAlert,
                    showCreateListAlert: $showCreateListAlert
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Task sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        // List sheets
        .sheet(item: $listsVM.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsVM)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedItemForDetails) { item in
            TaskDetailsDrawer(task: item, viewModel: listsVM, categories: listsVM.categories)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedItemForSchedule) { item in
            CommitmentSelectionSheet(task: item, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        // Batch delete confirmation
        .alert("Delete \(taskListVM.selectedCount) task\(taskListVM.selectedCount == 1 ? "" : "s")?", isPresented: $taskListVM.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await taskListVM.batchDeleteTasks() }
            }
        } message: {
            Text("This will permanently delete the selected tasks and their commitments.")
        }
        // Batch move category sheet
        .sheet(isPresented: $taskListVM.showBatchMovePicker) {
            BatchMoveCategorySheet(
                viewModel: taskListVM,
                onMoveToProject: { projectId in
                    await taskListVM.batchMoveToProject(projectId)
                }
            )
            .drawerStyle()
        }
        // Batch commit sheet
        .sheet(isPresented: $taskListVM.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: taskListVM)
                .drawerStyle()
        }
        // Create project alert
        .alert("Create Project", isPresented: $showCreateProjectAlert) {
            TextField("Project title", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { newProjectTitle = "" }
            Button("Create") {
                let title = newProjectTitle
                newProjectTitle = ""
                _Concurrency.Task { @MainActor in
                    await taskListVM.createProjectFromSelected(title: title)
                }
            }
        } message: {
            Text("Enter a name for the new project")
        }
        // Create list alert
        .alert("Create List", isPresented: $showCreateListAlert) {
            TextField("List title", text: $newListTitle)
            Button("Cancel", role: .cancel) { newListTitle = "" }
            Button("Create") {
                let title = newListTitle
                newListTitle = ""
                _Concurrency.Task { @MainActor in
                    await taskListVM.createListFromSelected(title: title)
                }
            }
        } message: {
            Text("Enter a name for the new list")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if taskListVM.isEditMode {
                    Button {
                        taskListVM.exitEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if taskListVM.isEditMode {
                    Button {
                        if taskListVM.allUncompletedSelected {
                            taskListVM.deselectAll()
                        } else {
                            taskListVM.selectAllUncompleted()
                        }
                    } label: {
                        Text(taskListVM.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            taskListVM.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .task {
            taskListVM.commitmentFilter = .uncommitted
            listsVM.commitmentFilter = .uncommitted

            isLoading = true
            async let t: () = fetchTasks()
            async let l: () = listsVM.fetchLists()
            _ = await (t, l)
            isLoading = false
        }
    }

    private func fetchTasks() async {
        await taskListVM.fetchTasks()
        await taskListVM.fetchCategories()
        await taskListVM.fetchCommittedTaskIds()
    }

    // MARK: - Item List

    /// Flattened task display items excluding project-contained tasks
    private var standaloneTaskDisplayItems: [FlatDisplayItem] {
        let projectTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil }.map { $0.id })
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil
            case .addSubtaskRow(let parentId): return !projectTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    /// Flattened list display items excluding project-contained lists
    private var standaloneListDisplayItems: [FlatListDisplayItem] {
        let projectListIds = Set(listsVM.filteredLists.filter { $0.projectId != nil }.map { $0.id })
        return listsVM.flattenedDisplayItems.filter { item in
            switch item {
            case .list(let list): return list.projectId == nil
            case .item(_, let listId): return !projectListIds.contains(listId)
            case .doneSection(let listId): return !projectListIds.contains(listId)
            case .addItemRow(let listId): return !projectListIds.contains(listId)
            }
        }
    }

    private var itemList: some View {
        List {
            // Tasks (excluding project-contained)
            ForEach(standaloneTaskDisplayItems) { item in
                switch item {
                case .priorityHeader:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case .task(let task):
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM,
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(task.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(task.id) }
                    )
                    .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .addSubtaskRow(let parentId):
                    InlineAddRow(
                        placeholder: "Subtask title",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await taskListVM.createSubtask(title: title, parentId: parentId) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .padding(.leading, 32)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)

                case .addTaskRow:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            // Lists (excluding project-contained)
            ForEach(standaloneListDisplayItems) { item in
                switch item {
                case .list(let list):
                    ListRow(
                        list: list,
                        viewModel: listsVM,
                        showIcon: true
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .item(let item, let listId):
                    ListItemRow(item: item, listId: listId, viewModel: listsVM)
                        .padding(.leading, 32)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowBackground(Color.clear)
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .doneSection(let listId):
                    ListDoneSection(listId: listId, viewModel: listsVM)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case .addItemRow(let listId):
                    InlineAddRow(
                        placeholder: "Item title",
                        buttonLabel: "Add items",
                        onSubmit: { title in await listsVM.createItem(title: title, listId: listId) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .padding(.leading, 32)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
                }
            }

            // Bottom spacer
            Color.clear
                .frame(height: 100)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    async let t: () = fetchTasks()
                    async let l: () = listsVM.fetchLists()
                    _ = await (t, l)
                    continuation.resume()
                }
            }
        }
    }
}
