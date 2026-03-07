//
//  CategoryDetailView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct CategoryDetailView: View {
    let category: Category

    @StateObject private var taskListVM: TaskListViewModel
    @StateObject private var projectsVM: ProjectsViewModel
    @StateObject private var listsVM: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false

    // Editable category name
    @State private var categoryName: String
    @FocusState private var isNameFocused: Bool
    private let categoryRepository = CategoryRepository()

    // Section collapse states
    @State private var isTasksSectionCollapsed = false
    @State private var isProjectsSectionCollapsed = false
    @State private var isListsSectionCollapsed = false

    // Navigation
    @State private var selectedProjectForNavigation: FocusTask?
    @State private var selectedListForNavigation: FocusTask?

    init(category: Category, authService: AuthService) {
        self.category = category
        _categoryName = State(initialValue: category.name)
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    // MARK: - Computed Properties

    private var categoryTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil }
    }

    private var categoryTaskDisplayItems: [FlatDisplayItem] {
        let projectTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil }.map { $0.id })
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil
            case .addSubtaskRow(let parentId): return !projectTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    private var categoryProjects: [FocusTask] {
        projectsVM.projects.filter { !$0.isCompleted && !$0.isCleared && $0.categoryId == category.id }
    }

    private var categoryLists: [FocusTask] {
        listsVM.lists.filter { !$0.isCompleted && !$0.isCleared && $0.categoryId == category.id }
    }

    private var isEmpty: Bool {
        categoryTasks.isEmpty && categoryProjects.isEmpty && categoryLists.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if category.isSystem {
                        HourglassIcon()
                            .fill(.primary, style: FillStyle(eoFill: true))
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "folder")
                            .font(.inter(size: 22, weight: .regular))
                            .foregroundColor(.primary)
                    }
                }

                if category.isSystem {
                    Text(category.name)
                        .pageTitleStyle()
                        .foregroundColor(.primary)
                } else {
                    TextField("Category name", text: $categoryName)
                        .pageTitleStyle()
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { saveName() }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if isLoading && isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { isNameFocused = false }
            } else if isEmpty {
                VStack(spacing: 4) {
                    Text("No items yet")
                        .font(AppStyle.Typography.emptyTitle)
                    Text("Tasks, projects, and lists in \"\(category.name)\" will appear here")
                        .font(AppStyle.Typography.emptySubtitle)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture { isNameFocused = false }
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
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await taskListVM.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == taskListVM.somedayCategory?.id
            )
                .drawerStyle()
        }
        // List sheets
        .sheet(item: $listsVM.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsVM)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedItemForSchedule) { item in
            ScheduleSelectionSheet(
                task: item,
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await listsVM.moveTaskToSomeday(item) }
                },
                isSomedayTask: item.categoryId == listsVM.somedayCategory?.id
            )
                .drawerStyle()
        }
        // Project sheets
        .sheet(item: $projectsVM.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsVM)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await projectsVM.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == projectsVM.somedayCategory?.id
            )
                .drawerStyle()
        }
        // Navigation
        .navigationDestination(item: $selectedListForNavigation) { list in
            ListContentView(list: list, viewModel: listsVM)
        }
        .navigationDestination(item: $selectedProjectForNavigation) { project in
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused { saveName() }
        }
        .task {
            taskListVM.selectedCategoryId = category.id
            isLoading = true
            async let cats: () = taskListVM.fetchCategories()
            async let cids: () = taskListVM.fetchScheduledTaskIds()
            _ = await (cats, cids)

            async let t: () = taskListVM.fetchTasks()
            async let p: () = projectsVM.fetchProjects()
            async let l: () = listsVM.fetchLists()
            _ = await (t, p, l)
            isLoading = false
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            // MARK: Tasks Section
            if !categoryTasks.isEmpty {
                tasksSectionHeader

                if !isTasksSectionCollapsed {
                    ForEach(categoryTaskDisplayItems) { item in
                        switch item {
                        case .priorityHeader(let priority):
                            PrioritySectionHeader(
                                priority: priority,
                                count: categoryTasks.filter { $0.priority == priority }.count,
                                isCollapsed: taskListVM.isPriorityCollapsed(priority),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        taskListVM.togglePriorityCollapsed(priority)
                                    }
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        case .task(let task):
                            FlatTaskRow(
                                task: task,
                                viewModel: taskListVM,
                                isEditMode: false,
                                isSelected: false,
                                onToggleCompletion: { t in
                                    taskListVM.requestToggleCompletion(t)
                                }
                            )
                            .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(task.parentTaskId != nil ? .visible : .hidden)

                        case .addSubtaskRow:
                            EmptyView()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)

                        case .addTaskRow:
                            EmptyView()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }

            // MARK: Projects Section
            if !categoryProjects.isEmpty {
                projectsSectionHeader

                if !isProjectsSectionCollapsed {
                    ForEach(categoryProjects) { project in
                        CategoryProjectRow(
                            project: project,
                            onTap: { selectedProjectForNavigation = project },
                            onEdit: { projectsVM.selectedProjectForDetails = project },
                            onSchedule: { projectsVM.selectedTaskForSchedule = project },
                            onDelete: {
                                await projectsVM.deleteProject(project)
                                await refreshData()
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // MARK: Quick Lists Section
            if !categoryLists.isEmpty {
                listsSectionHeader

                if !isListsSectionCollapsed {
                    ForEach(categoryLists) { list in
                        CategoryListRow(
                            list: list,
                            onTap: { selectedListForNavigation = list },
                            onEdit: { listsVM.selectedListForDetails = list },
                            onSchedule: { listsVM.selectedItemForSchedule = list },
                            onDelete: {
                                await listsVM.deleteList(list)
                                await refreshData()
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
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
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded { isNameFocused = false })
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await refreshData()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func refreshData() async {
        async let t: () = taskListVM.fetchTasks()
        async let p: () = projectsVM.fetchProjects()
        async let l: () = listsVM.fetchLists()
        _ = await (t, p, l)
    }

    private func saveName() {
        let trimmed = categoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != category.name else {
            categoryName = category.name
            return
        }
        var updated = category
        updated.name = trimmed
        _Concurrency.Task {
            do {
                try await categoryRepository.updateCategory(updated)
                NotificationCenter.default.post(name: .projectListChanged, object: nil)
            } catch {}
        }
    }

    // MARK: - Section Headers

    private var tasksSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTasksSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
                Text("Tasks")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(categoryTasks.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isTasksSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var projectsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isProjectsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundColor(.appRed)
                Text("Projects")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(categoryProjects.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isProjectsSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var listsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isListsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
                Text("Quick Lists")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(categoryLists.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isListsSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Category Project Row

private struct CategoryProjectRow: View {
    let project: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { showDeleteConfirmation = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Project", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { _Concurrency.Task { await onDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(project.title)\"?")
        }
    }
}

// MARK: - Category List Row

private struct CategoryListRow: View {
    let list: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { showDeleteConfirmation = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete List", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { _Concurrency.Task { await onDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(list.title)\"?")
        }
    }
}
