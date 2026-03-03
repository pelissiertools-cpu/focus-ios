//
//  UnassignedView.swift
//  Focus IOS
//

import SwiftUI

struct UnassignedView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    private var isEmpty: Bool {
        taskListVM.uncompletedTasks.isEmpty &&
        listsVM.filteredLists.isEmpty &&
        projectsVM.filteredProjects.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "tray")
                    .font(.inter(size: 22, weight: .regular))
                    .foregroundColor(.primary)

                Text("Unassign")
                    .font(.inter(size: 28, weight: .regular))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Tasks, lists, and projects without a schedule will appear here")
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
        // Project navigation
        .navigationDestination(item: $projectsVM.selectedProjectForContent) { project in
            ProjectContentView(project: project, viewModel: projectsVM)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                }
            }
        }
        .task {
            taskListVM.commitmentFilter = .uncommitted
            listsVM.commitmentFilter = .uncommitted
            projectsVM.commitmentFilter = .uncommitted

            isLoading = true
            async let t: () = fetchTasks()
            async let l: () = listsVM.fetchLists()
            async let p: () = projectsVM.fetchProjects()
            _ = await (t, l, p)
            isLoading = false
        }
    }

    private func fetchTasks() async {
        await taskListVM.fetchTasks()
        await taskListVM.fetchCategories()
        await taskListVM.fetchCommittedTaskIds()
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            // Tasks
            ForEach(taskListVM.flattenedDisplayItems) { item in
                switch item {
                case .priorityHeader:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case .task(let task):
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM
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

            // Lists
            ForEach(listsVM.flattenedDisplayItems) { item in
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

            // Projects
            ForEach(projectsVM.filteredProjects) { project in
                Button {
                    projectsVM.selectedProjectForContent = project
                } label: {
                    HStack(spacing: 12) {
                        Text(project.title)
                            .font(.inter(.body, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.inter(size: 12, weight: .semiBold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                .listRowBackground(Color.clear)
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }
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
                    async let p: () = projectsVM.fetchProjects()
                    _ = await (t, l, p)
                    continuation.resume()
                }
            }
        }
    }
}
