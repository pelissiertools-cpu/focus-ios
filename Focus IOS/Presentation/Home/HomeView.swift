//
//  HomeView.swift
//  Focus IOS
//

import SwiftUI
import Auth

private enum HomeAddBarTitleFocus: Hashable {
    case task, list, project
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @StateObject private var goalsViewModel: GoalsViewModel
    @State private var showSettings = false
    @State private var showSearch = false

    // Category management
    @State private var showCreateCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var categoryToRename: Category?
    @State private var renameCategoryName = ""
    @State private var categoryToDelete: Category?

    // Task list VM for add bar task creation
    @StateObject private var taskListVM: TaskListViewModel

    private let authService: AuthService

    // Unified add bar state
    @State private var showingAddBar = false
    @State private var addBarMode: TaskType = .task

    // Compact add-task bar state
    @State private var addTaskTitle = ""
    @State private var addTaskSubtasks: [DraftSubtaskEntry] = []
    @State private var addTaskCategoryId: UUID? = nil
    @State private var addTaskScheduleExpanded = false
    @State private var addTaskTimeframe: Timeframe = .daily
    @State private var addTaskSection: Section = .todo
    @State private var addTaskDates: Set<Date> = []
    @State private var addTaskPriority: Priority = .low
    @State private var addTaskOptionsExpanded = false
    @State private var addTaskDatesSnapshot: Set<Date> = []
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false
    @FocusState private var focusedSubtaskId: UUID?

    // Compact add-list bar state
    @State private var addListTitle = ""
    @State private var addListItems: [DraftSubtaskEntry] = []
    @State private var addListCategoryId: UUID? = nil
    @State private var addListScheduleExpanded = false
    @State private var addListTimeframe: Timeframe = .daily
    @State private var addListSection: Section = .todo
    @State private var addListDates: Set<Date> = []
    @State private var addListDatesSnapshot: Set<Date> = []
    @State private var addListOptionsExpanded = false
    @State private var addListPriority: Priority = .low
    @FocusState private var focusedListItemId: UUID?

    // Compact add-project bar state
    @State private var addProjectTitle = ""
    @State private var addProjectDraftTasks: [DraftTask] = []
    @State private var addProjectCategoryId: UUID? = nil
    @State private var addProjectScheduleExpanded = false
    @State private var addProjectTimeframe: Timeframe = .daily
    @State private var addProjectSection: Section = .todo
    @State private var addProjectDates: Set<Date> = []
    @State private var addProjectDatesSnapshot: Set<Date> = []
    @State private var addProjectOptionsExpanded = false
    @State private var addProjectPriority: Priority = .low
    @FocusState private var focusedProjectTaskId: UUID?

    // Unified title focus
    @FocusState private var addBarTitleFocus: HomeAddBarTitleFocus?

    // Toast notification state
    @State private var toastMessage = ""
    @State private var showToast = false

    // Pre-computed title emptiness checks
    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddListTitleEmpty: Bool {
        addListTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddProjectTitleEmpty: Bool {
        addProjectTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var inboxCount: Int {
        taskListVM.tasks.filter {
            !$0.isCompleted && $0.projectId == nil && $0.parentTaskId == nil
            && $0.categoryId == nil
            && !taskListVM.scheduledTaskIds.contains($0.id)
        }.count
    }

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsViewModel = StateObject(wrappedValue: ListsViewModel(authService: authService))
        _goalsViewModel = StateObject(wrappedValue: GoalsViewModel(authService: authService))
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                // Top gradient mist
                VStack {
                    LinearGradient(
                        colors: [
                            Color(UIColor { traits in
                                traits.userInterfaceStyle == .dark
                                    ? UIColor(red: 0x2E/255.0, green: 0x59/255.0, blue: 0xF4/255.0, alpha: 0.08)
                                    : UIColor(red: 0xFF/255.0, green: 0x8D/255.0, blue: 0x00/255.0, alpha: 0.064)
                            }),
                            Color(UIColor { traits in
                                traits.userInterfaceStyle == .dark
                                    ? UIColor(red: 0x2E/255.0, green: 0x59/255.0, blue: 0xF4/255.0, alpha: 0.03)
                                    : UIColor(red: 0xFF/255.0, green: 0x8D/255.0, blue: 0x00/255.0, alpha: 0.024)
                            }),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: AppStyle.Layout.gradientMistHeight)
                    .ignoresSafeArea(edges: .top)
                    Spacer()
                }
                ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.section) {
                        Color.clear.frame(height: 0).id("homeScrollTop")
                        // MARK: - Date Header
                        VStack(alignment: .leading, spacing: 0) {
                            Text(currentDayName)
                                .font(.helveticaNeue(size: 23.5))
                                .tracking(-0.245)
                                .foregroundColor(.secondary)
                            formattedDateView
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, AppStyle.Spacing.page)
                        .padding(.top, AppStyle.Spacing.compact)
                        .padding(.bottom, 60)

                        // MARK: - Today / Inbox
                        HStack(spacing: AppStyle.Spacing.comfortable) {
                            homeCard(title: "Today", customIcon: {
                                Image(systemName: "sun.max")
                                    .font(.helveticaNeue(size: 15, weight: .medium))
                                    .foregroundColor(.accentOrange)
                                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                    .background(Color.dividerBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                            }) {
                                viewModel.selectedMenuItem = .today
                            }
                            homeCard(title: "Inbox", customIcon: {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.helveticaNeue(size: 15, weight: .medium))
                                    .foregroundColor(.inboxGreen)
                                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                    .background(Color.inboxBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                            }, count: inboxCount) {
                                viewModel.selectedMenuItem = .inbox
                            }
                        }
                        .padding(.horizontal, AppStyle.Spacing.page)

                        // MARK: - Schedule / Completed
                        HStack(spacing: AppStyle.Spacing.comfortable) {
                            homeCard(title: "Upcoming", customIcon: {
                                Image(systemName: "calendar")
                                    .font(.helveticaNeue(size: 15, weight: .medium))
                                    .foregroundColor(.appRed)
                                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                    .background(Color.scheduledBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                            }) {
                                viewModel.selectedMenuItem = .assign
                            }
                            homeCard(title: "Completed", customIcon: {
                                Image(systemName: "archivebox")
                                    .font(.helveticaNeue(size: 15, weight: .medium))
                                    .foregroundColor(.appText)
                                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                            }) {
                                viewModel.selectedMenuItem = .archive
                            }
                        }
                        .padding(.horizontal, AppStyle.Spacing.page)

                        // MARK: - Library Divider
                        homeSectionDivider(title: "LIBRARY")

                        // MARK: - Projects / Quick Lists / Goals
                        HStack(spacing: AppStyle.Spacing.compact) {
                            homeCardCompact(title: "Quick lists", icon: "checklist") {
                                viewModel.selectedMenuItem = .quickLists
                            }
                            homeCardCompact(title: "Projects", customIcon: {
                                Image("ProjectIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 15, height: 15)
                                    .foregroundColor(.appText)
                            }) {
                                viewModel.selectedMenuItem = .projects
                            }
                            homeCardCompact(title: "Goals", customIcon: {
                                Image("TargetIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: AppStyle.Layout.tinyIcon, height: AppStyle.Layout.tinyIcon)
                                    .foregroundColor(.appText)
                            }) {
                                viewModel.selectedMenuItem = .goals
                            }
                        }
                        .padding(.horizontal, AppStyle.Spacing.page)


                        // MARK: - Categories Section
                        categoriesSectionHeader

                        if !viewModel.categories.isEmpty {
                            GeometryReader { geo in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppStyle.Spacing.comfortable) {
                                        ForEach(viewModel.categories) { category in
                                            categoryCard(category, containerWidth: geo.size.width)
                                        }
                                    }
                                    .padding(.horizontal, AppStyle.Spacing.page)
                                    .padding(.vertical, 3)
                                }
                            }
                            .frame(height: AppStyle.Layout.touchTarget + 6)
                            .padding(.top, -AppStyle.Spacing.compact)
                            .padding(.bottom, -AppStyle.Spacing.compact)
                        }

                        // MARK: - Main Focus Section
                        if !viewModel.mainFocusTasks.isEmpty {
                            // Divider + header
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
                                Rectangle()
                                    .fill(Color.cardBorder)
                                    .frame(height: AppStyle.Border.thin)

                                Button {
                                    viewModel.selectedMenuItem = .today
                                } label: {
                                    HStack(spacing: AppStyle.Spacing.compact) {
                                        Image(systemName: "target")
                                            .font(.helveticaNeue(size: AppStyle.Layout.sectionDividerIcon, weight: .medium))
                                            .foregroundColor(.focusBlue)
                                            .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                            .background(Color.todayBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                                        Text("Main Focus")
                                            .font(.inter(size: 14, weight: .bold))
                                            .foregroundColor(.focusBlue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, AppStyle.Spacing.page)

                            // Task list
                            VStack(spacing: 0) {
                                ForEach(viewModel.mainFocusTasks) { task in
                                    Button {
                                        viewModel.selectedMenuItem = .today
                                    } label: {
                                        HStack(spacing: AppStyle.Spacing.compact) {
                                            Circle()
                                                .stroke(Color.gray, lineWidth: 1.5)
                                                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                                                .frame(width: AppStyle.Layout.iconBadge)

                                            Text(task.title)
                                                .font(AppStyle.Typography.itemTitle)
                                                .foregroundColor(.primary)
                                                .lineLimit(2)

                                            Spacer()
                                        }
                                        .padding(.vertical, AppStyle.Spacing.compact)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppStyle.Spacing.page)
                            .padding(.top, -(AppStyle.Spacing.section / 2))
                        }

                        // MARK: - Pinned Section
                        if !viewModel.pinnedItems.isEmpty {
                            homeSectionDivider(title: "PINNED", assetIcon: "PushPin")

                            VStack(spacing: 0) {
                                ForEach(viewModel.pinnedItems) { item in
                                    pinnedItemRow(item)
                                }
                            }
                            .padding(.horizontal, AppStyle.Spacing.page)
                            .padding(.top, -(AppStyle.Spacing.section / 2))
                        }
                    }
                    .padding(.bottom, 120)
                }
                .onAppear {
                    scrollProxy.scrollTo("homeScrollTop", anchor: .top)
                }
                } // ScrollViewReader

                // MARK: - Bottom Bar
                if !showingAddBar {
                    homeBottomBar {
                        withAnimation(AppStyle.Anim.modeSwitch) {
                            addBarMode = .task
                            showingAddBar = true
                        }
                    }
                    .transition(.opacity)
                }

                // MARK: - Add Bar Overlay
                if showingAddBar {
                    // Scrim
                    Color.black.opacity(AppStyle.Opacity.scrim)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(50)

                    // Tap-to-dismiss + add bar
                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(AppStyle.Anim.modeSwitch) {
                                    dismissActiveAddBar()
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

                // MARK: - Toast Notification
                if showToast {
                    VStack {
                        Text(toastMessage)
                            .font(.inter(.subheadline, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, AppStyle.Spacing.section)
                            .padding(.vertical, AppStyle.Spacing.compact)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .zIndex(200)
                }
            }
            .navigationDestination(item: $viewModel.selectedMenuItem) { menuItem in
                if menuItem == .archive {
                    ArchiveView(authService: authService)
                } else if menuItem == .inbox {
                    BacklogView(authService: authService, tasksOnly: true)
                } else if menuItem == .assign {
                    ScheduledView(authService: authService)
                } else if menuItem == .backlog {
                    BacklogView(authService: authService)
                } else if menuItem == .today {
                    TodayView(authService: authService)
                } else if menuItem == .projects {
                    ProjectsListPage(viewModel: viewModel, authService: authService)
                } else if menuItem == .quickLists {
                    QuickListsPage(viewModel: viewModel, authService: authService)
                } else if menuItem == .goals {
                    GoalsListPage(viewModel: viewModel, authService: authService)
                } else {
                    HomePlaceholderPage(title: menuItem.rawValue)
                }
            }
            .navigationDestination(item: $viewModel.selectedPinnedItem) { item in
                if item.type == .project {
                    ProjectContentView(project: item, viewModel: projectsViewModel)
                } else if item.type == .goal {
                    GoalContentView(goal: item, viewModel: goalsViewModel)
                } else {
                    ListContentView(list: item, viewModel: listsViewModel)
                }
            }
            .navigationDestination(item: $viewModel.selectedCategory) { category in
                CategoryDetailView(category: category, authService: authService)
            }
            // Settings presented via overlay with left-edge slide
            .navigationDestination(isPresented: $showSearch) {
                BacklogView(authService: authService, startWithSearch: true)
            }
            .alert("New Category", isPresented: $showCreateCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    newCategoryName = ""
                    guard !name.isEmpty else { return }
                    if let userId = authService.currentUser?.id {
                        _Concurrency.Task { await viewModel.createCategory(name: name, userId: userId) }
                    }
                }
            } message: {
                Text("Enter a name for the new category")
            }
            .alert("Rename Category", isPresented: Binding(
                get: { categoryToRename != nil },
                set: { if !$0 { categoryToRename = nil } }
            )) {
                TextField("Category name", text: $renameCategoryName)
                Button("Cancel", role: .cancel) { categoryToRename = nil }
                Button("Save") {
                    let name = renameCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, let category = categoryToRename else { return }
                    categoryToRename = nil
                    _Concurrency.Task { await viewModel.renameCategory(category, newName: name) }
                }
            } message: {
                Text("Enter a new name")
            }
            .alert("Delete Category", isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { categoryToDelete = nil }
                Button("Delete", role: .destructive) {
                    guard let category = categoryToDelete else { return }
                    categoryToDelete = nil
                    _Concurrency.Task { await viewModel.deleteCategory(id: category.id) }
                }
            } message: {
                if let category = categoryToDelete {
                    Text("Are you sure you want to delete \"\(category.name)\"? Items in this category will become uncategorized.")
                }
            }
            .navigationBarHidden(true)
            .task {
                // Fetch projects/lists for count badges
                if viewModel.projects.isEmpty {
                    await viewModel.fetchProjects(showLoading: true)
                }
                if viewModel.lists.isEmpty {
                    await viewModel.fetchLists()
                }
                if viewModel.goals.isEmpty {
                    await viewModel.fetchGoals()
                }
                await taskListVM.fetchScheduledTaskIds()
                await taskListVM.fetchTasks()
                await taskListVM.fetchCategories()
                await viewModel.fetchCategories()
                // Pre-load categories for add bar
                await projectsViewModel.fetchProjects()
                await listsViewModel.fetchLists()
                await goalsViewModel.fetchGoals()

                // Pre-fetch today schedules so TodayView opens instantly
                await prefetchTodaySchedules()
                await viewModel.fetchMainFocusTasks()
            }
            // Add bar: auto-focus on open
            .onChange(of: showingAddBar) { _, isShowing in
                if isShowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        switch addBarMode {
                        case .task, .goal: addBarTitleFocus = .task
                        case .list: addBarTitleFocus = .list
                        case .project: addBarTitleFocus = .project
                        }
                    }
                }
            }
            // Add bar: focus transfer on mode switch
            .onChange(of: addBarMode) { _, newMode in
                guard showingAddBar else { return }
                focusedSubtaskId = nil
                focusedListItemId = nil
                focusedProjectTaskId = nil
                switch newMode {
                case .task, .goal: addBarTitleFocus = .task
                case .list: addBarTitleFocus = .list
                case .project: addBarTitleFocus = .project
                }
            }
            // Task schedule expansion focus management
            .onChange(of: addTaskScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedSubtaskId = nil
                }
            }
            .onChange(of: addBarTitleFocus) { _, focus in
                if focus == .task && addTaskScheduleExpanded {
                    withAnimation(AppStyle.Anim.toggle) {
                        addTaskScheduleExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId) { _, subtaskId in
                if subtaskId != nil && addTaskScheduleExpanded {
                    withAnimation(AppStyle.Anim.toggle) {
                        addTaskScheduleExpanded = false
                    }
                }
            }
            // List schedule expansion focus management
            .onChange(of: addListScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedListItemId = nil
                }
            }
            .onChange(of: focusedListItemId) { _, itemId in
                if itemId != nil && addListScheduleExpanded {
                    withAnimation(AppStyle.Anim.toggle) {
                        addListScheduleExpanded = false
                    }
                }
            }
            // Project schedule expansion focus management
            .onChange(of: addProjectScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedProjectTaskId = nil
                }
            }
            .onChange(of: focusedProjectTaskId) { _, taskId in
                if taskId != nil && addProjectScheduleExpanded {
                    withAnimation(AppStyle.Anim.toggle) {
                        addProjectScheduleExpanded = false
                    }
                }
            }
        }
        .overlay {
            if showSettings {
                settingsPanel
                    .transition(.move(edge: .trailing))
            }
        }
    }

    // MARK: - Settings Panel (slides from left)

    private var settingsPanel: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(AppStyle.Anim.expand) {
                                showSettings = false
                            }
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
        }
    }

    // MARK: - Home Card

    private func homeCard<Icon: View>(title: String, icon: String? = nil, @ViewBuilder customIcon: () -> Icon = { EmptyView() }, count: Int? = nil, centered: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack {
                if centered { Spacer() }
                Text(title)
                    .font(.helveticaNeue(size: 15.22, weight: .medium))
                    .tracking(-0.158)
                    .foregroundColor(.appText)
                if let count, count > 0 {
                    Text("(\(count))")
                        .font(.helveticaNeue(size: 11.08, weight: .medium))
                        .tracking(-0.11)
                        .lineSpacing(13.4 - 11.08)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.helveticaNeue(size: 17.3, weight: .medium))
                        .foregroundColor(.appText)
                        .frame(width: AppStyle.Layout.pillButton, alignment: .center)
                } else {
                    customIcon()
                        .frame(width: AppStyle.Layout.pillButton, alignment: .center)
                }
            }
            .padding(AppStyle.Spacing.section)
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
            .contentShape(Rectangle())
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .cardBorderOverlay()
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    private func homeCardCompact<Icon: View>(title: String, icon: String? = nil, @ViewBuilder customIcon: () -> Icon = { EmptyView() }, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: AppStyle.Spacing.small) {
                Text(title)
                    .font(.helveticaNeue(size: 13, weight: .medium))
                    .tracking(-0.135)
                    .foregroundColor(.appText)
                    .lineLimit(1)
                if let icon {
                    Image(systemName: icon)
                        .font(.helveticaNeue(size: 15, weight: .medium))
                        .foregroundColor(.appText)
                } else {
                    customIcon()
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
            .contentShape(Rectangle())
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .cardBorderOverlay()
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Card

    private func categoryCard(_ category: Category, containerWidth: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.selectedCategory = category
        } label: {
            Text(category.name)
                .font(.helveticaNeue(size: 13, weight: .medium))
                .tracking(-0.135)
                .foregroundColor(.appText)
                .lineLimit(1)
                .padding(.vertical, AppStyle.Spacing.comfortable)
                .padding(.horizontal, AppStyle.Spacing.compact)
                .frame(width: (containerWidth - AppStyle.Spacing.page * 2 - AppStyle.Spacing.comfortable * 2) / 3)
                .background(Color.categoryBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                .cardBorderOverlay()
                .cardShadow()
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameCategoryName = category.name
                categoryToRename = category
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                categoryToDelete = category
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Pinned Item Row

    @ViewBuilder
    private func pinnedItemRow(_ item: FocusTask) -> some View {
        Button {
            viewModel.selectedPinnedItem = item
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                if item.type == .project {
                    Image("ProjectIcon")
                        .renderingMode(.template)
                        .resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.secondary)
                        .frame(width: AppStyle.Layout.iconBadge)
                } else if item.type == .goal {
                    Image("TargetIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: AppStyle.Layout.smallIcon, height: AppStyle.Layout.smallIcon)
                        .foregroundColor(.secondary)
                        .frame(width: AppStyle.Layout.iconBadge)
                } else {
                    Image(systemName: "checklist")
                        .font(.inter(.body, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: AppStyle.Layout.iconBadge)
                }

                Text(item.title)
                    .font(.helveticaNeue(.body, weight: .regular))
                    .foregroundColor(.appText)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, AppStyle.Spacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ContextMenuItems.pinButton(isPinned: true) {
                _Concurrency.Task { await viewModel.togglePin(item) }
            }
        }
    }

    // MARK: - Section Divider

    private func homeSectionDivider(title: String, assetIcon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
            if let assetIcon = assetIcon {
                Image(assetIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppStyle.Layout.sectionDividerIcon, height: AppStyle.Layout.sectionDividerIcon)
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
            } else {
                Text(title)
                    .homeSectionLabelStyle()
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.page)
    }

    // MARK: - Categories Section Header

    private var categoriesSectionHeader: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
            HStack {
                Text("CATEGORIES")
                    .homeSectionLabelStyle()
                    .foregroundColor(.primary)
                Spacer()
                Menu {
                    Button {
                        newCategoryName = ""
                        showCreateCategoryAlert = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                    }

                    if !viewModel.categories.isEmpty {
                        Divider()
                        ForEach(viewModel.categories) { category in
                            Menu(category.name) {
                                Button {
                                    renameCategoryName = category.name
                                    categoryToRename = category
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    categoryToDelete = category
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.subheadline, weight: .semiBold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.tiny)
                        .contentShape(Rectangle())
                        .offset(x: AppStyle.Spacing.content, y: 0)
                }
            }
            .frame(minHeight: 17.56)
        }
        .padding(.horizontal, AppStyle.Spacing.page)
    }

    // MARK: - Date Helpers

    private var currentDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var currentDateShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: Date())
    }

    private var formattedDateView: some View {
        let now = Date()
        let cal = Calendar.current
        let day = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let month = monthFormatter.string(from: now)

        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22:     suffix = "nd"
        case 3, 23:     suffix = "rd"
        default:        suffix = "th"
        }

        let baseSize: CGFloat = 13.7
        let smallSize: CGFloat = baseSize - 1.8
        let yearStr = String(format: "%d", year)

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(month) \(day)")
                .font(.helveticaNeue(size: baseSize))
                .tracking(-0.158)
            Text("\(suffix)__\(yearStr)")
                .font(.helveticaNeue(size: smallSize))
                .tracking(-0.158)
        }
    }

    private var currentWeekString: String {
        let week = Calendar.current.component(.weekOfYear, from: Date())
        return String(format: "week__%02d", week)
    }


    // MARK: - Bottom Bar

    /// Bar shape with circular notch cut out of the top center
    private struct NotchedBarShape: Shape {
        let notchRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            let notchCenter = CGPoint(x: rect.midX, y: 0)
            let notchR = notchRadius
            // Angle where the notch arc meets the top edge
            let startAngle = Angle.degrees(180)
            let endAngle = Angle.degrees(0)

            var path = Path()
            // Start top-left
            path.move(to: CGPoint(x: 0, y: 0))
            // Line to left edge of notch
            path.addLine(to: CGPoint(x: notchCenter.x - notchR, y: 0))
            // Semicircular notch (downward arc)
            path.addArc(center: notchCenter, radius: notchR,
                        startAngle: startAngle, endAngle: endAngle,
                        clockwise: true)
            // Line to top-right
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            // Down to bottom-right
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            // Across bottom
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            // Close
            path.closeSubpath()
            return path
        }
    }

    private func homeBottomBar(action: @escaping () -> Void) -> some View {
        let notchRadius: CGFloat = (AppStyle.Layout.fab / 2) + 4
        return VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .top) {
                // Bar background with notch
                VStack(spacing: 0) {
                    HStack {
                        // Profile button
                        Button(action: {
                            withAnimation(AppStyle.Anim.expand) {
                                showSettings = true
                            }
                        }) {
                            Image(systemName: "person")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.appText)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Search button
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.appText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
                .background(
                    NotchedBarShape(notchRadius: notchRadius)
                        .fill(Color.cardBackground)
                        .barShadow()
                )
                .overlay(
                    NotchedBarShape(notchRadius: notchRadius)
                        .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
                )

                // Plus button (centered in notch)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    action()
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
                .accessibilityLabel("Add")
                .offset(y: -(AppStyle.Layout.fab / 2))
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
        case .task, .goal: addTaskBar
        case .list: addListBar
        case .project: addProjectBar
        }
    }

    // MARK: - Compact Add Task Bar

    private var addTaskBar: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Create a new task", text: $addTaskTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .task)
                .submitLabel(.return)
                .onSubmit {
                    saveTask()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            // Subtasks
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            // Schedule expansion (calendar section)
            if addTaskScheduleExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
                    Picker("Section", selection: $addTaskSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $addTaskDates,
                        selectedTimeframe: $addTaskTimeframe
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)

                // Schedule mode action row
                HStack {
                    Button {
                        withAnimation(AppStyle.Anim.toggle) {
                            addTaskDates.removeAll()
                            addTaskScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(AppStyle.Anim.toggle) {
                            addTaskScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Sub-task row: [Sub-task] ... [AI Breakdown] [Checkmark]
            if !addTaskScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Button {
                    addNewSubtask()
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "plus")
                            .font(.inter(.caption))
                        Text("Sub-task")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // More options pill
                Button {
                    withAnimation(AppStyle.Anim.toggle) {
                        addTaskOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // AI Breakdown
                Button {
                    generateBreakdown()
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        if isGeneratingBreakdown {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                .font(.inter(.subheadline, weight: .semiBold))
                                .foregroundColor(!isAddTaskTitleEmpty ? .blue : .primary)
                        }
                        Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                            .font(.inter(.caption, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(
                        !isAddTaskTitleEmpty ? Color.pillBackground : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

                // Submit button (checkmark)
                Button {
                    saveTask()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                        .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                        .background(
                            isAddTaskTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddTaskTitleEmpty)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Bottom row: [Category] [Schedule] [Priority]
            if addTaskOptionsExpanded && !addTaskScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Menu {
                    Button {
                        addTaskCategoryId = nil
                    } label: {
                        if addTaskCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(taskListVM.categories) { category in
                        Button {
                            addTaskCategoryId = category.id
                        } label: {
                            if addTaskCategoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "folder")
                            .font(.inter(.caption))
                        Text(LocalizedStringKey(taskCategoryPillLabel))
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Button {
                    if !addTaskScheduleExpanded {
                        addTaskDatesSnapshot = addTaskDates
                    }
                    withAnimation(AppStyle.Anim.toggle) {
                        addTaskScheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.caption))
                        Text("Schedule")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(!addTaskDates.isEmpty ? .white : .black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(!addTaskDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            addTaskPriority = priority
                        } label: {
                            if addTaskPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Circle()
                            .fill(addTaskPriority.dotColor)
                            .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                        Text(addTaskPriority.displayName)
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.small)
            }

            Spacer().frame(height: AppStyle.Spacing.page)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Compact Add List Bar

    private var addListBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new list", text: $addListTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .list)
                .submitLabel(.return)
                .onSubmit {
                    saveList()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            DraftSubtaskListEditor(
                subtasks: $addListItems,
                focusedSubtaskId: $focusedListItemId,
                onAddNew: { addNewListItem() },
                placeholder: "Item"
            )

            // Schedule expansion
            if addListScheduleExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
                    Picker("Section", selection: $addListSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $addListDates,
                        selectedTimeframe: $addListTimeframe
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)

                HStack {
                    Button {
                        withAnimation(AppStyle.Anim.toggle) {
                            addListDates.removeAll()
                            addListScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = addListDates != addListDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(AppStyle.Anim.toggle) {
                            addListScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 1: [Item] [...] Spacer [Checkmark]
            if !addListScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Button {
                    addNewListItem()
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "plus")
                            .font(.inter(.caption))
                        Text("Item")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(AppStyle.Anim.toggle) {
                        addListOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    saveList()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isAddListTitleEmpty ? .secondary : .white)
                        .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                        .background(
                            isAddListTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddListTitleEmpty)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if addListOptionsExpanded && !addListScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Menu {
                    Button {
                        addListCategoryId = nil
                    } label: {
                        if addListCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(listsViewModel.categories) { category in
                        Button {
                            addListCategoryId = category.id
                        } label: {
                            if addListCategoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "folder")
                            .font(.inter(.caption))
                        Text(LocalizedStringKey(listCategoryPillLabel))
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Button {
                    addListDatesSnapshot = addListDates
                    withAnimation(AppStyle.Anim.toggle) {
                        addListScheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.caption))
                        Text("Schedule")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(!addListDates.isEmpty ? .white : .black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(!addListDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            addListPriority = priority
                        } label: {
                            if addListPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Circle()
                            .fill(addListPriority.dotColor)
                            .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                        Text(addListPriority.displayName)
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.small)
            }

            Spacer().frame(height: AppStyle.Spacing.page)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Compact Add Project Bar

    private var addProjectBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new project", text: $addProjectTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .project)
                .submitLabel(.return)
                .onSubmit {
                    saveProject()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            // Tasks + subtasks area
            if !addProjectDraftTasks.isEmpty {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    ForEach(addProjectDraftTasks) { task in
                        projectTaskDraftRow(task: task)
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.compact)
                .padding(.bottom, AppStyle.Spacing.small)
            }

            // Schedule expansion
            if addProjectScheduleExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
                    Picker("Section", selection: $addProjectSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $addProjectDates,
                        selectedTimeframe: $addProjectTimeframe
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)

                HStack {
                    Button {
                        withAnimation(AppStyle.Anim.toggle) {
                            addProjectDates.removeAll()
                            addProjectScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = addProjectDates != addProjectDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(AppStyle.Anim.toggle) {
                            addProjectScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 1: [Task] [...] Spacer [Checkmark]
            if !addProjectScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Button {
                    addNewProjectTask()
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "plus")
                            .font(.inter(.caption))
                        Text("Task")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(AppStyle.Anim.toggle) {
                        addProjectOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    saveProject()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isAddProjectTitleEmpty ? .secondary : .white)
                        .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                        .background(
                            isAddProjectTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddProjectTitleEmpty)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if addProjectOptionsExpanded && !addProjectScheduleExpanded {
            HStack(spacing: AppStyle.Spacing.compact) {
                Menu {
                    Button {
                        addProjectCategoryId = nil
                    } label: {
                        if addProjectCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(projectsViewModel.categories) { category in
                        Button {
                            addProjectCategoryId = category.id
                        } label: {
                            if addProjectCategoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "folder")
                            .font(.inter(.caption))
                        Text(LocalizedStringKey(projectCategoryPillLabel))
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Button {
                    addProjectDatesSnapshot = addProjectDates
                    withAnimation(AppStyle.Anim.toggle) {
                        addProjectScheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.caption))
                        Text("Schedule")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(!addProjectDates.isEmpty ? .white : .black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(!addProjectDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            addProjectPriority = priority
                        } label: {
                            if addProjectPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Circle()
                            .fill(addProjectPriority.dotColor)
                            .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                        Text(addProjectPriority.displayName)
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.small)
            }

            Spacer().frame(height: AppStyle.Spacing.page)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Project Task Draft Row

    @ViewBuilder
    private func projectTaskDraftRow(task: DraftTask) -> some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Image(systemName: "circle")
                .font(.inter(.caption2))
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: projectTaskBinding(for: task.id), axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($focusedProjectTaskId, equals: task.id)
                .lineLimit(1...3)
                .onChange(of: projectTaskBinding(for: task.id).wrappedValue) { _, newValue in
                    if newValue.contains("\n") {
                        if let idx = addProjectDraftTasks.firstIndex(where: { $0.id == task.id }) {
                            addProjectDraftTasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                        }
                        addNewProjectSubtask(toTask: task.id)
                    }
                }

            Button {
                removeProjectTask(id: task.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "circle")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Sub-task", text: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.inter(.body))
                    .textFieldStyle(.plain)
                    .focused($focusedProjectTaskId, equals: subtask.id)
                    .lineLimit(1...3)
                    .onChange(of: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id).wrappedValue) { _, newValue in
                        if newValue.contains("\n") {
                            if let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == task.id }),
                               let sIdx = addProjectDraftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtask.id }) {
                                addProjectDraftTasks[tIdx].subtasks[sIdx].title = newValue.replacingOccurrences(of: "\n", with: "")
                            }
                            addNewProjectSubtask(toTask: task.id)
                        }
                    }

                Button {
                    removeProjectSubtask(id: subtask.id, fromTask: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, AppStyle.Spacing.compact)
            .padding(.vertical, AppStyle.Spacing.small)
        }
        .padding(.top, AppStyle.Spacing.comfortable)

        // "+ Sub-task" button
        Button {
            addNewProjectSubtask(toTask: task.id)
        } label: {
            HStack(spacing: AppStyle.Spacing.tiny) {
                Image(systemName: "plus")
                    .font(.inter(.subheadline))
                Text("Sub-task")
                    .font(.inter(.subheadline))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, AppStyle.Spacing.tiny)
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .padding(.top, AppStyle.Spacing.compact)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    // MARK: - Add Task Helpers

    private var taskCategoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func generateBreakdown() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isGeneratingBreakdown = true
        _Concurrency.Task { @MainActor in
            do {
                let aiService = AIService()
                let suggestions = try await aiService.generateSubtasks(title: title, description: nil)
                withAnimation(AppStyle.Anim.toggle) {
                    addTaskSubtasks.append(contentsOf: suggestions.map { DraftSubtaskEntry(title: $0) })
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail
            }
            isGeneratingBreakdown = false
        }
    }

    private func saveTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addTaskCategoryId
        let priority = addTaskPriority
        let scheduleEnabled = !addTaskDates.isEmpty
        let timeframe = addTaskTimeframe
        let section = addTaskSection
        let dates = addTaskDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentToast("Task was created")

        addBarTitleFocus = .task
        focusedSubtaskId = nil

        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskDates = []
        addTaskOptionsExpanded = false
        addTaskScheduleExpanded = false
        addTaskPriority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithSchedules(
                title: title,
                categoryId: categoryId,
                priority: priority,
                subtaskTitles: subtasksToCreate,
                scheduleAfterCreate: scheduleEnabled,
                selectedTimeframe: timeframe,
                selectedSection: section,
                selectedDates: dates,
                hasScheduledTime: false,
                scheduledTime: nil
            )

            if scheduleEnabled && !dates.isEmpty {
                await focusViewModel.fetchSchedules()
            }
        }
    }

    private func addNewSubtask() {
        addBarTitleFocus = .task
        let newEntry = DraftSubtaskEntry()
        withAnimation(AppStyle.Anim.quick) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func dismissAddTask() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskPriority = .low
        addTaskOptionsExpanded = false
        addTaskScheduleExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        addBarTitleFocus = nil
        focusedSubtaskId = nil
    }

    // MARK: - Add List Helpers

    private var listCategoryPillLabel: String {
        if let categoryId = addListCategoryId,
           let category = listsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveList() {
        let title = addListTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let itemTitles = addListItems
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addListCategoryId
        let priority = addListPriority
        let scheduleEnabled = !addListDates.isEmpty
        let timeframe = addListTimeframe
        let section = addListSection
        let dates = addListDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentToast("List was created")

        addBarTitleFocus = .list
        focusedListItemId = nil

        addListTitle = ""
        addListItems = []
        addListDates = []
        addListScheduleExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low

        _Concurrency.Task { @MainActor in
            await listsViewModel.createList(title: title, categoryId: categoryId, priority: priority)

            if let createdList = listsViewModel.lists.first {
                for itemTitle in itemTitles {
                    await listsViewModel.createItem(title: itemTitle, listId: createdList.id)
                }
                if !itemTitles.isEmpty {
                    listsViewModel.expandedLists.insert(createdList.id)
                }

                if scheduleEnabled && !dates.isEmpty {
                    for date in dates {
                        let schedule = Schedule(
                            userId: createdList.userId,
                            taskId: createdList.id,
                            timeframe: timeframe,
                            section: section,
                            scheduleDate: date,
                            sortOrder: 0,
                            scheduledTime: nil,
                            durationMinutes: nil
                        )
                        _ = try? await listsViewModel.scheduleRepository.createSchedule(schedule)
                    }
                    await focusViewModel.fetchSchedules()
                    await listsViewModel.fetchScheduledTaskIds()
                }
            }

            // Refresh Home's list display
            await viewModel.fetchLists()
        }
    }

    private func addNewListItem() {
        addBarTitleFocus = .list
        let newEntry = DraftSubtaskEntry()
        withAnimation(AppStyle.Anim.quick) {
            addListItems.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedListItemId = newEntry.id
        }
    }

    private func dismissAddList() {
        addListTitle = ""
        addListItems = []
        addListCategoryId = nil
        addListScheduleExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low
        addListDates = []
        addBarTitleFocus = nil
        focusedListItemId = nil
    }

    // MARK: - Add Project Helpers

    private var projectCategoryPillLabel: String {
        if let categoryId = addProjectCategoryId,
           let category = projectsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveProject() {
        let title = addProjectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let draftTasks = addProjectDraftTasks.filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let categoryId = addProjectCategoryId
        let priority = addProjectPriority
        let scheduleEnabled = !addProjectDates.isEmpty
        let timeframe = addProjectTimeframe
        let section = addProjectSection
        let dates = addProjectDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentToast("Project was created")

        addBarTitleFocus = .project
        focusedProjectTaskId = nil

        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectDates = []
        addProjectScheduleExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low

        _Concurrency.Task { @MainActor in
            guard let projectId = await projectsViewModel.saveNewProject(
                title: title,
                categoryId: categoryId,
                priority: priority,
                draftTasks: draftTasks
            ) else { return }

            if scheduleEnabled && !dates.isEmpty {
                guard let userId = projectsViewModel.authService.currentUser?.id else { return }
                for date in dates {
                    let schedule = Schedule(
                        userId: userId,
                        taskId: projectId,
                        timeframe: timeframe,
                        section: section,
                        scheduleDate: date,
                        sortOrder: 0,
                        scheduledTime: nil,
                        durationMinutes: nil
                    )
                    _ = try? await projectsViewModel.scheduleRepository.createSchedule(schedule)
                }
                await focusViewModel.fetchSchedules()
                await projectsViewModel.fetchScheduledTaskIds()
            }

            // Refresh Home's project display
            await viewModel.fetchProjects()
        }
    }

    private func projectTaskBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: { addProjectDraftTasks.first(where: { $0.id == taskId })?.title ?? "" },
            set: { newValue in
                if let idx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) {
                    addProjectDraftTasks[idx].title = newValue
                }
            }
        )
    }

    private func projectSubtaskBinding(forSubtask subtaskId: UUID, inTask taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }),
                      let s = addProjectDraftTasks[tIdx].subtasks.first(where: { $0.id == subtaskId })
                else { return "" }
                return s.title
            },
            set: { newValue in
                if let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }),
                   let sIdx = addProjectDraftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) {
                    addProjectDraftTasks[tIdx].subtasks[sIdx].title = newValue
                }
            }
        )
    }

    private func addNewProjectTask() {
        let newTask = DraftTask()
        withAnimation(AppStyle.Anim.quick) {
            addProjectDraftTasks.append(newTask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newTask.id
        }
    }

    private func addNewProjectSubtask(toTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let newSubtask = DraftSubtask(title: "")
        withAnimation(AppStyle.Anim.quick) {
            addProjectDraftTasks[tIdx].subtasks.append(newSubtask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newSubtask.id
        }
    }

    private func removeProjectTask(id: UUID) {
        withAnimation(AppStyle.Anim.quick) {
            addProjectDraftTasks.removeAll { $0.id == id }
        }
    }

    private func removeProjectSubtask(id: UUID, fromTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        withAnimation(AppStyle.Anim.quick) {
            addProjectDraftTasks[tIdx].subtasks.removeAll { $0.id == id }
        }
    }

    private func dismissAddProject() {
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectCategoryId = nil
        addProjectScheduleExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low
        addProjectDates = []
        addBarTitleFocus = nil
        focusedProjectTaskId = nil
    }

    // MARK: - Shared Dismiss

    private func dismissActiveAddBar() {
        guard showingAddBar else { return }
        dismissAddTask()
        dismissAddList()
        dismissAddProject()
        showingAddBar = false
    }

    // MARK: - Toast

    private func presentToast(_ message: String) {
        withAnimation(AppStyle.Anim.modeSwitch) {
            toastMessage = message
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(AppStyle.Anim.modeSwitch) {
                showToast = false
            }
        }
    }

    // MARK: - Today Schedule Pre-fetch

    private func prefetchTodaySchedules() async {
        let cache = AppDataCache.shared
        // Skip if already cached for today
        if let cachedDate = cache.todayScheduleDate,
           Calendar.current.isDateInToday(cachedDate) {
            return
        }
        let scheduleRepository = ScheduleRepository()
        do {
            let focus = try await scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .focus)
            let todo = try await scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .todo)
            let overdue = try await scheduleRepository.fetchOverdueSchedules()
            cache.todayFocusSchedules = focus
            cache.todayTodoSchedules = todo
            cache.overdueSchedules = overdue
            cache.todayScheduleDate = Date()
        } catch {
            // Non-critical — TodayView will fetch on its own
        }
    }
}

// MARK: - Home Project Row

struct HomeProjectRow: View {
    let project: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

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
        .padding(.vertical, AppStyle.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Home List Row

struct HomeListRow: View {
    let list: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

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
        .padding(.vertical, AppStyle.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Placeholder Page

private struct HomePlaceholderPage: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text(title)
                .font(.inter(.title2, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.top, AppStyle.Spacing.section)
            Spacer()
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
        }
    }
}
