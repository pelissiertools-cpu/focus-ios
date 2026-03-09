//
//  CategoryDetailView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct CategoryDetailView: View {
    let category: Category
    private let authService: AuthService

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

    // Add bar
    @State private var showingAddBar = false
    @State private var addBarMode: TaskType = .task

    init(category: Category, authService: AuthService) {
        self.category = category
        self.authService = authService
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
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: AppStyle.Spacing.compact) {
                    Group {
                        if category.isSystem {
                            HourglassIcon()
                                .fill(Color.appText, style: FillStyle(eoFill: true))
                                .frame(width: 15, height: 15)
                        } else {
                            Image(systemName: "folder")
                                .font(.helveticaNeue(size: 15, weight: .medium))
                                .foregroundColor(.appText)
                        }
                    }
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

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
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.top, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.compact)

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { isNameFocused = false }
                } else if isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No items yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Tasks, projects, and lists in \"\(category.name)\" will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppStyle.Spacing.page)
                    .contentShape(Rectangle())
                    .onTapGesture { isNameFocused = false }
                } else {
                    itemList
                }
            }

            // MARK: - FAB Button
            if !showingAddBar {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                addBarMode = .task
                                showingAddBar = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.title2, weight: .semiBold))
                                .foregroundColor(.appText)
                                .frame(width: AppStyle.Layout.fab, height: AppStyle.Layout.fab)
                                .background(Color.cardBackground, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
                                )
                                .fabShadow()
                        }
                        .accessibilityLabel("Add item")
                        .padding(.trailing, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.page)
                    }
                }
                .transition(.opacity)
            }

            // MARK: - Add Bar Overlay
            if showingAddBar {
                Color.black.opacity(AppStyle.Opacity.scrim)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(50)

                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                showingAddBar = false
                            }
                        }

                    VStack(spacing: 0) {
                        addBarModeSelector
                            .padding(.vertical, AppStyle.Spacing.comfortable)

                        activeAddBar
                            .padding(.bottom, AppStyle.Spacing.compact)
                    }
                    .contentShape(Rectangle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
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
                focusViewModel: focusViewModel
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
                focusViewModel: focusViewModel
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
                focusViewModel: focusViewModel
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
                        .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                withAnimation(AppStyle.Anim.toggle) {
                                    taskListVM.sortOption = option
                                }
                            } label: {
                                if taskListVM.sortOption == option {
                                    Label(option.displayName, systemImage: "checkmark")
                                } else {
                                    Text(option.displayName)
                                }
                            }
                        }

                        Divider()

                        ForEach(taskListVM.sortOption.directionOrder, id: \.self) { direction in
                            Button {
                                withAnimation(AppStyle.Anim.toggle) {
                                    taskListVM.sortDirection = direction
                                }
                            } label: {
                                if taskListVM.sortDirection == direction {
                                    Label(direction.displayName(for: taskListVM.sortOption), systemImage: "checkmark")
                                } else {
                                    Text(direction.displayName(for: taskListVM.sortOption))
                                }
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }

                    Divider()

                    Button {
                        taskListVM.enterEditMode()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                        .background(Color.pillBackground, in: Circle())
                }
                .accessibilityLabel("More options")
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

    // MARK: - Add Bar Mode Selector

    private var addBarModeSelector: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            addBarModeCircle(mode: .task, icon: "checkmark.circle")
            addBarModeCircle(mode: .list, icon: "checklist")
            addBarModeCircle(mode: .project, icon: "folder", customImage: "ProjectIcon")
            Spacer()
        }
        .padding(.horizontal)
    }

    private func addBarModeCircle(mode: TaskType, icon: String, customImage: String? = nil) -> some View {
        let isActive = addBarMode == mode
        return Button {
            withAnimation(AppStyle.Anim.buttonTap) {
                addBarMode = mode
            }
        } label: {
            Group {
                if let customImage {
                    Image(customImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.inter(.body, weight: .medium))
            .foregroundColor(isActive ? .white : .primary)
            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
            .glassEffect(
                isActive
                    ? .regular.tint(.black).interactive()
                    : .regular.interactive(),
                in: .circle
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active Add Bar

    @ViewBuilder
    private var activeAddBar: some View {
        switch addBarMode {
        case .task, .goal:
            AddTaskBar(
                taskListVM: taskListVM,
                authService: authService,
                initialCategoryId: category.id,
                onSaved: {
                    _Concurrency.Task { await refreshData() }
                },
                onDismiss: {
                    withAnimation(AppStyle.Anim.modeSwitch) {
                        showingAddBar = false
                    }
                }
            )
        case .list:
            AddListBar(
                listsViewModel: listsVM,
                initialCategoryId: category.id,
                onSaved: {
                    _Concurrency.Task { await refreshData() }
                },
                onDismiss: {
                    withAnimation(AppStyle.Anim.modeSwitch) {
                        showingAddBar = false
                    }
                }
            )
        case .project:
            AddProjectBar(
                projectsViewModel: projectsVM,
                initialCategoryId: category.id,
                onSaved: {
                    _Concurrency.Task { await refreshData() }
                },
                onDismiss: {
                    withAnimation(AppStyle.Anim.modeSwitch) {
                        showingAddBar = false
                    }
                }
            )
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
                                    withAnimation(AppStyle.Anim.toggle) {
                                        taskListVM.togglePriorityCollapsed(priority)
                                    }
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.section, bottom: 0, trailing: AppStyle.Spacing.section))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        case .task(let task):
                            FlatTaskRow(
                                task: task,
                                viewModel: taskListVM,
                                isEditMode: taskListVM.isEditMode,
                                isSelected: taskListVM.selectedTaskIds.contains(task.id),
                                onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                                onToggleCompletion: { t in
                                    taskListVM.requestToggleCompletion(t)
                                }
                            )
                            .padding(.leading, task.parentTaskId != nil ? AppStyle.Insets.nestedRow.leading : 0)
                            .listRowInsets(AppStyle.Insets.row)
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
                        .listRowInsets(AppStyle.Insets.row)
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
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // Bottom spacer
            Color.clear
                .frame(height: 100)
                .listRowInsets(AppStyle.Insets.zero)
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
            withAnimation(AppStyle.Anim.toggle) {
                isTasksSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "checkmark.circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
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
        .padding(.top, AppStyle.Spacing.tiny)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var projectsSectionHeader: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isProjectsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image("ProjectIcon")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
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
        .padding(.top, AppStyle.Spacing.section)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var listsSectionHeader: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isListsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "checklist")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
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
        .padding(.top, AppStyle.Spacing.section)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
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
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image("ProjectIcon")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppStyle.Spacing.compact)
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
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: "checklist")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppStyle.Spacing.compact)
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
