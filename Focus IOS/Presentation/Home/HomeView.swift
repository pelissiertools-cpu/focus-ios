//
//  HomeView.swift
//  Focus IOS
//

import SwiftUI
import Auth

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

    // Add bar state
    @State private var showingAddBar = false
    @State private var addBarMode: TaskType = .task

    // Toast notification state
    @State private var toastMessage = ""
    @State private var showToast = false

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
                        // Space for fixed header + fade gradient
                        Color.clear.frame(height: 90)

                        // MARK: - Daily Progress
                        if viewModel.todayTaskCount > 0 {
                            dailyProgressCard
                                .padding(.horizontal, AppStyle.Spacing.page)
                                .padding(.bottom, AppStyle.Spacing.section)
                        }

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
                        Rectangle()
                            .fill(Color.cardBorder)
                            .frame(height: AppStyle.Border.thin)
                            .padding(.horizontal, AppStyle.Spacing.page)

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

                                        Text("Today's Focus")
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
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
                                Rectangle()
                                    .fill(Color.cardBorder)
                                    .frame(height: AppStyle.Border.thin)

                                HStack(spacing: AppStyle.Spacing.compact) {
                                    Image("PushPin")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: AppStyle.Layout.sectionDividerIcon, height: AppStyle.Layout.sectionDividerIcon)
                                        .foregroundColor(.appText)
                                        .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                                        .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                                    Text("Pinboard")
                                        .font(.inter(size: 14, weight: .bold))
                                        .foregroundColor(.appText)
                                }
                            }
                            .padding(.horizontal, AppStyle.Spacing.page)

                            VStack(spacing: 0) {
                                ForEach(viewModel.pinnedItems) { item in
                                    pinnedItemRow(item)
                                }
                            }
                            .padding(.horizontal, AppStyle.Spacing.page)
                            .padding(.top, -(AppStyle.Spacing.section / 2))
                        }

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
                    }
                    .padding(.bottom, 120)
                }
                .onAppear {
                    scrollProxy.scrollTo("homeScrollTop", anchor: .top)
                }
                } // ScrollViewReader

                // MARK: - Fixed Header
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 10) {
                        Button(action: {
                            withAnimation(AppStyle.Anim.expand) {
                                showSettings = true
                            }
                        }) {
                            Image(systemName: "person")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
                                )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            if let name = authService.displayName {
                                Text(name.components(separatedBy: " ").first ?? name)
                                    .font(.inter(size: 22, weight: .bold))
                                    .foregroundColor(.appText)
                            }

                            HStack(spacing: 0) {
                                Text(currentDayName)
                                Text(", ")
                                formattedDateView
                            }
                            .font(.helveticaNeue(size: 13.7, weight: .bold))
                            .tracking(-0.158)
                            .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, AppStyle.Spacing.page)
                    .padding(.top, AppStyle.Spacing.compact)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
                    .background(
                        Color.appBackground
                            .overlay(
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
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .ignoresSafeArea(edges: .top)
                    )

                    // Smooth fade transition
                    ZStack {
                        LinearGradient(
                            colors: [Color.appBackground, Color.appBackground.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        LinearGradient(
                            colors: [
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
                    }
                    .frame(height: 40)
                    .allowsHitTesting(false)

                    Spacer()
                }

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
                    Color(UIColor { traits in
                        traits.userInterfaceStyle == .dark
                            ? UIColor.white.withAlphaComponent(0.08)
                            : UIColor.black.withAlphaComponent(0.15)
                    })
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(50)

                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                withAnimation(AppStyle.Anim.modeSwitch) {
                                    showingAddBar = false
                                }
                            }

                        AddBar(
                            config: .home,
                            categories: taskListVM.categories,
                            activeMode: $addBarMode,
                            onSave: { result in
                                switch result {
                                case .task: presentToast("Task was created")
                                case .list: presentToast("List was created")
                                case .project: presentToast("Project was created")
                                }
                                switch result {
                                case .task(let r):
                                    _Concurrency.Task { @MainActor in
                                        let taskId = await taskListVM.createTaskWithSchedules(
                                            title: r.title,
                                            categoryId: r.categoryId,
                                            priority: r.priority,
                                            subtaskTitles: r.subtaskTitles,
                                            scheduleAfterCreate: r.schedule != nil,
                                            selectedTimeframe: r.schedule?.timeframe ?? .daily,
                                            selectedSection: r.schedule?.section ?? .todo,
                                            selectedDates: r.schedule?.dates ?? [],
                                            hasScheduledTime: false,
                                            scheduledTime: nil
                                        )
                                        if let taskId {
                                            r.schedule?.scheduleNotificationIfNeeded(taskId: taskId, taskTitle: r.title)
                                        }
                                        if r.schedule != nil {
                                            await focusViewModel.fetchSchedules()
                                        }
                                    }
                                case .list(let r):
                                    _Concurrency.Task { @MainActor in
                                        await listsViewModel.createList(title: r.title, categoryId: r.categoryId, priority: r.priority)
                                        if let createdList = listsViewModel.lists.first {
                                            for itemTitle in r.itemTitles {
                                                await listsViewModel.createItem(title: itemTitle, listId: createdList.id)
                                            }
                                            if !r.itemTitles.isEmpty {
                                                listsViewModel.expandedLists.insert(createdList.id)
                                            }
                                            if let sched = r.schedule {
                                                for date in sched.dates {
                                                    let schedule = Schedule(
                                                        userId: createdList.userId,
                                                        taskId: createdList.id,
                                                        timeframe: sched.timeframe,
                                                        section: sched.section,
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
                                        await viewModel.fetchLists()
                                    }
                                case .project(let r):
                                    _Concurrency.Task { @MainActor in
                                        guard let projectId = await projectsViewModel.saveNewProject(
                                            title: r.title,
                                            categoryId: r.categoryId,
                                            priority: r.priority,
                                            draftTasks: r.draftTasks
                                        ) else { return }
                                        if let sched = r.schedule {
                                            guard let userId = projectsViewModel.authService.currentUser?.id else { return }
                                            for date in sched.dates {
                                                let schedule = Schedule(
                                                    userId: userId,
                                                    taskId: projectId,
                                                    timeframe: sched.timeframe,
                                                    section: sched.section,
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
                                        await viewModel.fetchProjects()
                                    }
                                }
                            },
                            onDismiss: {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                withAnimation(AppStyle.Anim.modeSwitch) {
                                    showingAddBar = false
                                }
                            }
                        )
                        .padding(.bottom, AppStyle.Spacing.compact)
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
                // Run progress card + main data in parallel so the card appears instantly
                async let progressTask: () = viewModel.fetchTodayProgress()

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

                // Ensure progress fetch completes
                _ = await progressTask
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionRefreshed)) { _ in
                _Concurrency.Task { @MainActor in
                    await reloadAllData()
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

    // MARK: - Daily Progress Card

    private var dailyProgressCard: some View {
        let total = viewModel.todayTaskCount
        let completed = viewModel.todayCompletedCount
        let progress = total > 0 ? Double(completed) / Double(total) : 0

        return Button {
            viewModel.selectedMenuItem = .today
        } label: {
            HStack(spacing: AppStyle.Spacing.section) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.cardBorder, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentOrange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(completed)/\(total)")
                        .font(.helveticaNeue(size: 13, weight: .bold))
                        .tracking(-0.135)
                        .foregroundColor(.appText)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks completed today")
                        .font(.helveticaNeue(size: 13, weight: .medium))
                        .tracking(-0.135)
                        .foregroundColor(.secondary)

                    if completed == total && total > 0 {
                        Text("All done!")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundColor(.accentOrange)
                    }
                }

                Spacer()
            }
            .padding(AppStyle.Spacing.section)
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .cardBorderOverlay()
            .cardShadow()
        }
        .buttonStyle(.plain)
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

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        let month = monthFormatter.string(from: now)

        return Text("\(month) \(day)")
            .font(.helveticaNeue(size: 13.7))
            .tracking(-0.158)
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


    // MARK: - Full Data Reload (after session refresh)

    private func reloadAllData() async {
        await viewModel.fetchProjects(showLoading: false)
        await viewModel.fetchLists()
        await viewModel.fetchGoals()
        await taskListVM.fetchScheduledTaskIds()
        await taskListVM.fetchTasks()
        await taskListVM.fetchCategories()
        await viewModel.fetchCategories()
        await projectsViewModel.fetchProjects()
        await listsViewModel.fetchLists()
        await goalsViewModel.fetchGoals()
        await prefetchTodaySchedules()
        await viewModel.fetchTodayProgress()
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
