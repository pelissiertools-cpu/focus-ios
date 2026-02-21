//
//  FocusTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

// MARK: - Focus View Mode

enum FocusViewMode: String, CaseIterable {
    case focus
    case schedule
}

// MARK: - Drawer Top Preference Key

struct DrawerTopPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FocusTabView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var viewModel: FocusTabViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @State private var showCalendarPicker = false
    @State private var viewMode: FocusViewMode = .focus

    @State private var showScheduleDrawer = false
    @State private var showSettings = false
    @State private var showTimeframePicker = false

    // Compact add-task bar state
    @State private var addTaskTitle = ""
    @State private var addTaskSubtasks: [DraftSubtaskEntry] = []
    @State private var addTaskPriority: Priority = .low
    @State private var addTaskCategoryId: UUID? = nil
    @State private var addTaskCategories: [Category] = []
    @FocusState private var isAddTaskFieldFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Date Navigator with integrated timeframe picker and pill row
                DateNavigator(
                    selectedDate: $viewModel.selectedDate,
                    selectedTimeframe: $viewModel.selectedTimeframe,
                    viewMode: $viewMode,
                    compact: viewMode == .schedule,
                    onCalendarTap: { showCalendarPicker = true },
                    onProfileTap: { showSettings = true },
                    showTimeframePicker: $showTimeframePicker
                )
                .opacity(viewModel.showAddTaskSheet ? 0 : 1)
                .allowsHitTesting(!viewModel.showAddTaskSheet)
                Color.clear.frame(height: 0)
                .onChange(of: viewModel.selectedDate) {
                    _Concurrency.Task { @MainActor in
                        await viewModel.fetchCommitments()
                    }
                }
                .onChange(of: viewModel.selectedTimeframe) {
                    _Concurrency.Task { @MainActor in
                        await viewModel.fetchCommitments()
                    }
                }

                if viewMode == .focus {
                    // MARK: - Focus Mode Content

                    // Content
                    if viewModel.isLoading {
                        ProgressView("Loading...")
                            .frame(maxHeight: .infinity)
                    } else {
                        focusList
                        .opacity(viewModel.showAddTaskSheet ? 0 : 1)
                        .allowsHitTesting(!viewModel.showAddTaskSheet)
                        .overlay {
                            if showTimeframePicker {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            showTimeframePicker = false
                                        }
                                    }
                            }
                        }
                    }
                } else {
                    // MARK: - Schedule Mode Content
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            // Layer 0: Timeline (full area, tap-to-dismiss)
                            CalendarTimelineView(timelineVM: viewModel.timelineVM, focusVM: viewModel)
                                .onTapGesture {
                                    if showScheduleDrawer {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            showScheduleDrawer = false
                                        }
                                    }
                                }

                            // Layer 2: Inline drawer (stays in tree to preserve DragGesture)
                            if showScheduleDrawer {
                                ScheduleDrawer(viewModel: viewModel, timelineVM: viewModel.timelineVM)
                                    .frame(height: geometry.size.height * 0.5)
                                    .opacity(viewModel.timelineVM.isDrawerRetractedForDrag ? 0 : 1)
                                    .allowsHitTesting(!viewModel.timelineVM.isDrawerRetractedForDrag)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .background(
                                        GeometryReader { drawerGeo in
                                            Color.clear.preference(
                                                key: DrawerTopPreference.self,
                                                value: drawerGeo.frame(in: .global).minY
                                            )
                                        }
                                    )

                                // Cancel bar appears when drawer is retracted during drag
                                if viewModel.timelineVM.isDrawerRetractedForDrag {
                                    DragCancelBar(isHighlighted: viewModel.timelineVM.isDragOverCancelZone)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                        .background(
                                            GeometryReader { cancelGeo in
                                                Color.clear
                                                    .onAppear {
                                                        viewModel.timelineVM.cancelZoneGlobalMinY = cancelGeo.frame(in: .global).minY
                                                    }
                                                    .onChange(of: cancelGeo.frame(in: .global).minY) { _, newY in
                                                        viewModel.timelineVM.cancelZoneGlobalMinY = newY
                                                    }
                                            }
                                        )
                                }
                            }

                            // Layer 3: FAB (only when drawer is closed)
                            if !showScheduleDrawer {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                showScheduleDrawer = true
                                            }
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.sf(.title2, weight: .semibold))
                                                .foregroundColor(.white)
                                                .frame(width: 56, height: 56)
                                                .glassEffect(.regular.tint(.appRed).interactive(), in: .circle)
                                                .shadow(radius: 4, y: 2)
                                        }
                                        .padding(.trailing, 20)
                                        .padding(.bottom, 20)
                                    }
                                }
                                .transition(.scale.combined(with: .opacity))
                            }

                        }
                        .onPreferenceChange(DrawerTopPreference.self) { top in
                            viewModel.timelineVM.drawerTopGlobalY = top
                        }
                        // Floating drag preview overlay (visible during drawer-to-timeline drag)
                        .overlay {
                            if let info = viewModel.timelineVM.scheduleDragInfo,
                               viewModel.timelineVM.timelineBlockDragId == nil {
                                GeometryReader { overlayGeo in
                                    let origin = overlayGeo.frame(in: .global).origin
                                    let localY = viewModel.timelineVM.scheduleDragLocation.y - origin.y

                                    ScheduleDragPreviewRow(
                                        info: info,
                                        isOverCancelZone: viewModel.timelineVM.isDragOverCancelZone
                                    )
                                    .frame(width: min(overlayGeo.size.width - 32, 340))
                                    .position(x: overlayGeo.size.width / 2, y: localY)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .toolbar(showScheduleDrawer && viewMode == .schedule ? .hidden : .visible, for: .tabBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .animation(.easeInOut(duration: 0.25), value: showScheduleDrawer)
            .animation(.easeInOut(duration: 0.25), value: viewModel.timelineVM.isDrawerRetractedForDrag)
            .onChange(of: selectedTab) {
                showSettings = false
            }
            .task {
                if !viewModel.hasLoadedInitialData {
                    await viewModel.fetchCommitments()
                }
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
            .sheet(item: $viewModel.selectedTaskForDetails) { task in
                let commitment = viewModel.commitments.first { $0.taskId == task.id }
                TaskDetailsDrawer(task: task, viewModel: viewModel, commitment: commitment)
                    .environmentObject(viewModel)
                    .drawerStyle()
            }
            .sheet(isPresented: $viewModel.showCommitSheet) {
                if let commitment = viewModel.selectedCommitmentForCommit,
                   let task = viewModel.tasksMap[commitment.taskId] {
                    CommitSheet(
                        commitment: commitment,
                        task: task,
                        viewModel: viewModel
                    )
                    .drawerStyle()
                }
            }
            .sheet(isPresented: $viewModel.showSubtaskCommitSheet) {
                if let subtask = viewModel.selectedSubtaskForCommit,
                   let parentCommitment = viewModel.selectedParentCommitmentForSubtaskCommit {
                    SubtaskCommitSheet(
                        subtask: subtask,
                        parentCommitment: parentCommitment,
                        viewModel: viewModel
                    )
                    .drawerStyle()
                }
            }
            .sheet(isPresented: $viewModel.showRescheduleSheet) {
                if let commitment = viewModel.selectedCommitmentForReschedule {
                    RescheduleSheet(commitment: commitment, focusViewModel: viewModel)
                        .drawerStyle()
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                SingleSelectCalendarPicker(
                    selectedDate: $viewModel.selectedDate,
                    timeframe: viewModel.selectedTimeframe
                )
                .drawerStyle()
            }
            .onChange(of: viewModel.showAddTaskSheet) { _, isShowing in
                if isShowing {
                    // Auto-expand Extra section if collapsed
                    if viewModel.addTaskSection == .extra && viewModel.isSectionCollapsed(.extra) {
                        viewModel.isExtraSectionCollapsed = false
                    }
                    isAddTaskFieldFocused = true
                }
            }

                // Tap-to-dismiss overlay when add task bar is active
                if viewModel.showAddTaskSheet {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dismissAddTask()
                            }
                        }
                        .allowsHitTesting(true)
                        .zIndex(50)

                    // Centered target section floating above the scrim
                    GeometryReader { geo in
                        let availableHeight = geo.size.height - 140
                        let sectionHeight = availableHeight * 0.5
                        VStack {
                            Spacer()
                            SectionView(
                                title: viewModel.addTaskSection == .focus ? "Focus" : "Extra",
                                section: viewModel.addTaskSection,
                                viewModel: viewModel
                            )
                            .padding(.horizontal)
                            .frame(minHeight: sectionHeight, alignment: .top)
                            Spacer()
                        }
                        .frame(height: availableHeight)
                    }
                    .allowsHitTesting(false)
                    .zIndex(75)

                    VStack {
                        Spacer()
                        addTaskBarOverlay
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            } // ZStack
            .background(Color.lightBackground.ignoresSafeArea())
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.showAddTaskSheet)
        }
    }

    // MARK: - Focus List

    private var focusList: some View {
        let flat = viewModel.flattenedDisplayItems
        return List {
            ForEach(Array(flat.enumerated()), id: \.element.id) { index, item in
                let nextIsSection: Bool = {
                    let nextIdx = index + 1
                    if nextIdx >= flat.count { return true }
                    if case .sectionHeader = flat[nextIdx] { return true }
                    return false
                }()
                switch item {
                case .sectionHeader(let section):
                    let isExtraHeader = section == .extra && index > 0
                    FocusSectionHeaderRow(section: section, viewModel: viewModel)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: isExtraHeader ? 20 : 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)

                case .commitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.focusConfig(for: commitment.section)
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            viewModel: viewModel,
                            fontOverride: commitment.section == .focus ? config.taskFont : nil,
                            verticalPaddingOverride: commitment.section == .focus ? config.verticalPadding : nil
                        )
                        .moveDisabled(false)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }
                    }

                case .subtask(let subtask, let parentCommitment):
                    FocusSubtaskRow(subtask: subtask, parentId: parentCommitment.taskId, parentCommitment: parentCommitment, viewModel: viewModel)
                        .padding(.leading, 32)
                        .padding(.trailing, 12)
                        .moveDisabled(subtask.isCompleted)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }

                case .addSubtaskRow(let parentId, _):
                    InlineAddRow(
                        placeholder: "Subtask",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                        verticalPadding: 6
                    )
                    .padding(.leading, 32)
                    .padding(.trailing, 12)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)

                case .completedCommitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.focusConfig(for: commitment.section)
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            viewModel: viewModel,
                            fontOverride: config.completedTaskFont,
                            verticalPaddingOverride: config.completedVerticalPadding
                        )
                        .opacity(config.completedOpacity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }
                    }

                case .emptyState(let section):
                    Group {
                        if section == .focus {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nothing to focus on")
                                    .font(.sf(.headline))
                                    .bold()
                                if !viewModel.showAddTaskSheet {
                                    Text("Tap + to add tasks")
                                        .font(.sf(.subheadline))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            VStack(alignment: .leading) {
                                Spacer(minLength: 0)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nothing to do")
                                        .font(.sf(.headline))
                                        .bold()
                                    if !viewModel.showAddTaskSheet {
                                        Text("Tap + to add tasks")
                                            .font(.sf(.subheadline))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 192 : 240, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.addTaskSection = section
                        viewModel.showAddTaskSheet = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .allDoneState:
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.sf(size: 34))
                            .foregroundColor(Color.completedPurple)
                            .scaleEffect(viewModel.allDoneCheckPulse ? 1.35 : 1.0)
                        Text("All done!")
                            .font(.sf(.title3, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.isFocusDoneExpanded.toggle()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .donePill:
                    DonePillView(
                        completedCommitments: viewModel.completedCommitmentsForSection(.extra),
                        section: .extra,
                        viewModel: viewModel
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .focusSpacer(let height):
                    Color.clear
                        .frame(height: height)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)

                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFocusDoneExpanded)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchCommitments()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Compact Add Task Bar

    private var addTaskBarOverlay: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Add new task", text: $addTaskTitle)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($isAddTaskFieldFocused)
                .submitLabel(.return)
                .onSubmit {
                    saveCompactTask()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Sub-tasks (expand downward when present)
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            // Sub-task row: [+ Sub-task] ... [AI Breakdown]
            HStack(spacing: 8) {
                Button {
                    addNewSubtask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.sf(.caption))
                        Text("Sub-task")
                            .font(.sf(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer()

                // AI Breakdown (compact, matching Log view style)
                Button {
                    generateBreakdown()
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingBreakdown {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                .font(.sf(.subheadline, weight: .semibold))
                        }
                        Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                            .font(.sf(.caption, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if !addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                            Capsule()
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            Color.commitGradientDark,
                                            Color.commitGradientLight,
                                            Color.commitGradientDark,
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                                .blur(radius: 6)
                        }
                    }
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.5), lineWidth: 1.5)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || isGeneratingBreakdown)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Bottom row: [Priority] [Category] ... [Checkmark]
            HStack(spacing: 8) {
                // Priority pill
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
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.sf(.caption))
                            .foregroundColor(addTaskPriority.dotColor)
                        Text(addTaskPriority.displayName)
                            .font(.sf(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addTaskPriority != .low ? addTaskPriority.dotColor : Color.black, in: Capsule())
                }

                // Category pill
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
                    ForEach(addTaskCategories) { category in
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
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.sf(.caption))
                        Text(LocalizedStringKey(addTaskCategoryPillLabel))
                            .font(.sf(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addTaskCategoryId != nil ? Color.appRed : Color.black, in: Capsule())
                }

                Spacer()

                // Submit button
                Button {
                    saveCompactTask()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color(.systemGray4)
                                : Color.appRed,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .onAppear { fetchCategories() }
    }

    private func saveCompactTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let section = viewModel.addTaskSection
        let priority = addTaskPriority
        let categoryId = addTaskCategoryId

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Transfer focus to title BEFORE removing subtask fields to prevent keyboard bounce
        isAddTaskFieldFocused = true
        focusedSubtaskId = nil

        // Clear fields immediately for rapid entry
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskPriority = .low
        addTaskCategoryId = nil
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await viewModel.createTaskWithSubtasks(title: title, section: section, subtaskTitles: subtasksToCreate, priority: priority, categoryId: categoryId)
        }
    }

    private func addNewSubtask() {
        // Hold focus on title to prevent keyboard drop during transition
        isAddTaskFieldFocused = true

        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func generateBreakdown() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        // Capture all existing subtask titles so AI avoids duplicating them
        let existingTitles = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        isGeneratingBreakdown = true
        _Concurrency.Task { @MainActor in
            do {
                let aiService = AIService()
                let suggestions = try await aiService.generateSubtasks(
                    title: title,
                    description: nil,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Keep manually-added subtasks, replace AI-generated ones
                    let manualSubtasks = addTaskSubtasks.filter { !$0.isAISuggested }
                    addTaskSubtasks = manualSubtasks + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail — user can tap again or add subtasks manually
            }
            isGeneratingBreakdown = false
        }
    }

    private var addTaskCategoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = addTaskCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func fetchCategories() {
        _Concurrency.Task {
            do {
                let categories = try await CategoryRepository().fetchCategories()
                await MainActor.run {
                    addTaskCategories = categories
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func dismissAddTask() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskPriority = .low
        addTaskCategoryId = nil
        hasGeneratedBreakdown = false
        viewModel.showAddTaskSheet = false
        isAddTaskFieldFocused = false
        focusedSubtaskId = nil
    }
}

// MARK: - Section View

struct SectionView: View {
    let title: String
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    @State private var showCapacityPopover = false

    var sectionCommitments: [Commitment] {
        viewModel.commitments.filter { commitment in
            commitment.section == section &&
            viewModel.isSameTimeframe(
                commitment.commitmentDate,
                timeframe: viewModel.selectedTimeframe,
                selectedDate: viewModel.selectedDate
            )
        }
    }

    var uncompletedCommitments: [Commitment] {
        viewModel.uncompletedCommitmentsForSection(section)
    }

    var completedCommitments: [Commitment] {
        viewModel.completedCommitmentsForSection(section)
    }

    private var focusConfig: FocusSectionConfig {
        viewModel.focusConfig(for: section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(title)
                    .font(.golosText(size: section == .focus ? 30 : 22))

                // Count display
                if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                    Text("\(sectionCommitments.count)/\(maxTasks)")
                        .font(.sf(size: 10))
                        .foregroundColor(.secondary)
                } else if !sectionCommitments.isEmpty {
                    Text("\(sectionCommitments.count)")
                        .font(.sf(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Add button (far right) - hidden when adding task
                Button {
                    if section == .focus && !viewModel.canAddTask(to: .focus) {
                        showCapacityPopover = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCapacityPopover = false
                        }
                    } else {
                        viewModel.addTaskSection = section
                        viewModel.showAddTaskSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.sf(.caption, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 26, height: 26)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCapacityPopover) {
                    let current = viewModel.taskCount(for: .focus)
                    let max = Section.focus.maxTasks(for: viewModel.selectedTimeframe) ?? 0
                    VStack(spacing: 4) {
                        Text("Focus section")
                            .font(.sf(.caption))
                            .foregroundStyle(.secondary)
                        Text("Section full")
                            .font(.sf(.subheadline, weight: .semibold))
                        Text("\(current)/\(max)")
                            .font(.sf(.title3, weight: .bold))
                            .foregroundStyle(Color.appRed)
                    }
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
                .opacity(viewModel.showAddTaskSheet ? 0 : 1)
                .allowsHitTesting(!viewModel.showAddTaskSheet)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if section == .extra {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleSectionCollapsed(section)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)

            // Committed Tasks (hidden when collapsed)
            if !viewModel.isSectionCollapsed(section) {
                if sectionCommitments.isEmpty && completedCommitments.isEmpty {
                    // Empty state left-aligned in the focus zone
                    VStack {
                        Spacer(minLength: 0)
                        Group {
                            if section == .focus {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nothing to focus on")
                                        .font(.sf(.headline))
                                        .bold()
                                    if !viewModel.showAddTaskSheet {
                                        Text("Tap + to start")
                                            .font(.sf(.subheadline))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("No task yet. Tap + to add one.")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 180 : nil, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.addTaskSection = section
                        viewModel.showAddTaskSheet = true
                    }
                } else {
                    VStack(spacing: 0) {
                        // Centering zone for uncompleted tasks
                        VStack(spacing: 0) {
                            if section == .focus && focusConfig.containerMinHeight > 0 {
                                Spacer(minLength: 0)
                            }

                            if uncompletedCommitments.isEmpty && !completedCommitments.isEmpty && section == .focus {
                                // All-done state
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.sf(size: 34))
                                        .foregroundColor(Color.completedPurple)
                                        .scaleEffect(viewModel.allDoneCheckPulse ? 1.35 : 1.0)
                                    Text("All done!")
                                        .font(.sf(.title3, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        viewModel.isFocusDoneExpanded.toggle()
                                    }
                                }
                            } else {
                                // Uncompleted commitments
                                ForEach(Array(uncompletedCommitments.enumerated()), id: \.element.id) { index, commitment in
                                    if let task = viewModel.tasksMap[commitment.taskId] {
                                        VStack(spacing: 0) {
                                            if index > 0 {
                                                Divider()
                                            }
                                            CommitmentRow(
                                                commitment: commitment,
                                                task: task,
                                                section: section,
                                                viewModel: viewModel,
                                                fontOverride: section == .focus ? focusConfig.taskFont : nil,
                                                verticalPaddingOverride: section == .focus ? focusConfig.verticalPadding : nil
                                            )
                                        }
                                    }
                                }
                            }

                            if section == .focus && focusConfig.containerMinHeight > 0 {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(minHeight: focusConfig.containerMinHeight > 0 ? focusConfig.containerMinHeight : nil)

                        // Completed commitments — below the centering zone for Focus, Done pill for Extra
                        if section == .focus && !completedCommitments.isEmpty && (viewModel.isFocusDoneExpanded || !uncompletedCommitments.isEmpty) {
                            ForEach(Array(completedCommitments.enumerated()), id: \.element.id) { index, commitment in
                                if let task = viewModel.tasksMap[commitment.taskId] {
                                    Divider()
                                    CommitmentRow(
                                        commitment: commitment,
                                        task: task,
                                        section: section,
                                        viewModel: viewModel,
                                        fontOverride: focusConfig.completedTaskFont,
                                        verticalPaddingOverride: focusConfig.completedVerticalPadding
                                    )
                                    .opacity(focusConfig.completedOpacity)
                                }
                            }
                        }

                        if section == .extra && !completedCommitments.isEmpty {
                            if !uncompletedCommitments.isEmpty {
                                Divider()
                                    .padding(.top, 8)
                            }

                            DonePillView(
                                completedCommitments: completedCommitments,
                                section: section,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
        }
        .frame(maxHeight: viewModel.showAddTaskSheet && viewModel.addTaskSection == section ? .infinity : nil, alignment: .top)
        .padding(.vertical)
        .padding(.horizontal, 8)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

// MARK: - Done Pill View

struct DonePillView: View {
    let completedCommitments: [Commitment]
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel

    private var isExpanded: Bool {
        !viewModel.isDoneSubsectionCollapsed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Done pill header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleDoneSubsectionCollapsed()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)

                    Text("Done")
                        .font(.sf(.subheadline, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("(\(completedCommitments.count))")
                        .font(.sf(.subheadline))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded completed tasks
            if isExpanded {
                let config = viewModel.focusConfig(for: section)
                VStack(spacing: 0) {
                    ForEach(Array(completedCommitments.enumerated()), id: \.element.id) { index, commitment in
                        if let task = viewModel.tasksMap[commitment.taskId] {
                            Divider()
                            CommitmentRow(
                                commitment: commitment,
                                task: task,
                                section: section,
                                viewModel: viewModel,
                                fontOverride: config.completedTaskFont,
                                verticalPaddingOverride: config.completedVerticalPadding
                            )
                            .opacity(config.completedOpacity)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Focus Section Header Row

struct FocusSectionHeaderRow: View {
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    @State private var showCapacityPopover = false

    private var sectionCommitments: [Commitment] {
        viewModel.commitments.filter { commitment in
            commitment.section == section &&
            viewModel.isSameTimeframe(
                commitment.commitmentDate,
                timeframe: viewModel.selectedTimeframe,
                selectedDate: viewModel.selectedDate
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(section.displayName)
                    .font(.golosText(size: section == .focus ? 30 : 22))

                // Count display
                if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                    HStack(spacing: 4) {
                        Text("\(sectionCommitments.count)/\(maxTasks)")
                            .font(.sf(size: 10))
                            .foregroundColor(.secondary)
                        if section == .extra {
                            Image(systemName: "chevron.right")
                                .font(.sf(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(viewModel.isSectionCollapsed(.extra) ? 0 : 90))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 1 }
                } else if !sectionCommitments.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(sectionCommitments.count)")
                            .font(.sf(size: 10))
                            .foregroundColor(.secondary)
                        if section == .extra {
                            Image(systemName: "chevron.right")
                                .font(.sf(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(viewModel.isSectionCollapsed(.extra) ? 0 : 90))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 1 }
                } else if section == .extra {
                    Image(systemName: "chevron.right")
                        .font(.sf(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(viewModel.isSectionCollapsed(.extra) ? 0 : 90))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 1 }
                }
            }

            Spacer()

            // Add button - hidden when adding task
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if section == .focus && !viewModel.canAddTask(to: .focus) {
                    showCapacityPopover = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCapacityPopover = false
                    }
                } else {
                    viewModel.addTaskSection = section
                    viewModel.showAddTaskSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.sf(.caption, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCapacityPopover) {
                let current = viewModel.taskCount(for: .focus)
                let max = Section.focus.maxTasks(for: viewModel.selectedTimeframe) ?? 0
                VStack(spacing: 4) {
                    Text("Focus section")
                        .font(.sf(.caption))
                        .foregroundStyle(.secondary)
                    Text("Section full")
                        .font(.sf(.subheadline, weight: .semibold))
                    Text("\(current)/\(max)")
                        .font(.sf(.title3, weight: .bold))
                        .foregroundStyle(Color.appRed)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            .opacity(viewModel.showAddTaskSheet ? 0 : 1)
            .allowsHitTesting(!viewModel.showAddTaskSheet)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if section == .extra {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleSectionCollapsed(section)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.secondary.opacity(0.7))
                .frame(height: 1)
        }
    }
}

// MARK: - Commitment Row

struct CommitmentRow: View {
    let commitment: Commitment
    let task: FocusTask
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    var fontOverride: Font? = nil
    var verticalPaddingOverride: CGFloat? = nil
    @State private var showDeleteConfirmation = false

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
    }

    private var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    private var isExpanded: Bool {
        viewModel.isExpanded(task.id)
    }

    private var childCount: Int {
        viewModel.childCount(for: commitment.id)
    }

    /// Can break down if: not daily (child commitments can also break down)
    private var canBreakdown: Bool {
        commitment.canBreakdown
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main task row
            HStack(spacing: 12) {
                // Child commitment indicator (indentation)
                if commitment.isChildCommitment {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(fontOverride ?? .sf(.title3, weight: .regular))
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                        if task.type == .list {
                            Image(systemName: "list.bullet")
                                .font(.sf(.subheadline))
                                .foregroundColor(.appRed)
                        }
                    }

                    // Subtask count indicator
                    if hasSubtasks {
                        let completedCount = subtasks.filter { $0.isCompleted }.count
                        Text("\(completedCount)/\(subtasks.count) subtasks")
                            .font(.sf(.caption))
                            .foregroundColor(.secondary)
                    }

                    // Child commitment count indicator
                    if childCount > 0 {
                        Text("\(childCount) broken down")
                            .font(.sf(.caption))
                            .foregroundColor(.appRed)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: section == .focus ? 38 : (section == .extra ? 36 : nil), alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleExpanded(task.id)
                    }
                }
                .contextMenu {
                    ContextMenuItems.editButton {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            viewModel.selectedTaskForDetails = task
                        }
                    }

                    Button(role: .destructive) {
                        _Concurrency.Task { @MainActor in
                            await viewModel.removeCommitment(commitment)
                        }
                    } label: {
                        Label(commitment.timeframe.removeLabel, systemImage: "minus.circle")
                    }

                    if !task.isCompleted {
                        Button {
                            viewModel.selectedCommitmentForReschedule = commitment
                            viewModel.showRescheduleSheet = true
                        } label: {
                            Label("Reschedule", systemImage: "calendar")
                        }

                        Button {
                            _Concurrency.Task { @MainActor in
                                await viewModel.pushCommitmentToNext(commitment)
                            }
                        } label: {
                            Label("Push to \(commitment.timeframe.nextTimeframeLabel)", systemImage: "arrow.turn.right.down")
                        }
                    }

                    Divider()

                    ContextMenuItems.deleteButton {
                        showDeleteConfirmation = true
                    }
                }
                .alert("Delete Task", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        _Concurrency.Task { @MainActor in
                            await viewModel.permanentlyDeleteTask(task)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete \"\(task.title)\"?")
                }

                // Commit button (for non-daily commitments)
                if canBreakdown {
                    Button {
                        viewModel.selectedCommitmentForCommit = commitment
                        viewModel.showCommitSheet = true
                    } label: {
                        Image(systemName: "arrow.down.forward.circle")
                            .font(.sf(.title3))
                            .foregroundColor(.appRed)
                    }
                    .buttonStyle(.plain)
                }

                // Completion button (right side for thumb access)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await viewModel.toggleTaskCompletion(task)
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.sf(.title3))
                        .foregroundColor(task.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, verticalPaddingOverride ?? (section == .focus ? 14 : 8))
            .padding(.horizontal, 16)

            // Subtasks are now rendered as flat list items (see focusList)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !task.isCompleted {
                Button(role: .destructive) {
                    _Concurrency.Task { @MainActor in
                        await viewModel.removeCommitment(commitment)
                    }
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
        }
    }
}

// MARK: - Focus Subtask Row

struct FocusSubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    let parentCommitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel

    /// Check if this subtask already has its own commitment
    private var hasOwnCommitment: Bool {
        viewModel.commitments.contains { $0.taskId == subtask.id }
    }

    /// Can break down if parent's timeframe is not daily and subtask doesn't have own commitment yet
    private var canBreakdown: Bool {
        parentCommitment.timeframe != .daily && !hasOwnCommitment
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.sf(.subheadline))
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            // Commit button for subtasks that can be committed to lower timeframes
            if canBreakdown {
                Button {
                    viewModel.selectedSubtaskForCommit = subtask
                    viewModel.selectedParentCommitmentForSubtaskCommit = parentCommitment
                    viewModel.showSubtaskCommitSheet = true
                } label: {
                    Image(systemName: "arrow.down.forward.circle")
                        .font(.sf(.subheadline))
                        .foregroundColor(.appRed)
                }
                .buttonStyle(.plain)
            }

            // Checkbox on right for thumb access
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.subheadline))
                    .foregroundColor(subtask.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
                    .frame(width: 22, alignment: .center)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            ContextMenuItems.editButton {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.selectedTaskForDetails = subtask
                }
            }

            Divider()

            ContextMenuItems.deleteButton {
                _Concurrency.Task { @MainActor in
                    await viewModel.deleteSubtask(subtask, parentId: parentId)
                }
            }
        }
    }
}

// MARK: - Drag Cancel Bar

private struct DragCancelBar: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.sf(.title3))
                .foregroundColor(isHighlighted ? .white : .secondary)

            Text("Drop to cancel")
                .font(.sf(.subheadline, weight: .medium))
                .foregroundColor(isHighlighted ? .white : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHighlighted ? Color.red.opacity(0.85) : Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 12, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }
}

// MARK: - Schedule Drag Preview Row

private struct ScheduleDragPreviewRow: View {
    let info: ScheduleDragInfo
    var isOverCancelZone: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: info.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.sf(.title3))
                .foregroundColor(info.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.taskTitle)
                    .font(.sf(.body))
                    .strikethrough(info.isCompleted)
                    .foregroundColor(info.isCompleted ? .secondary : .primary)
                    .lineLimit(1)

                if let subtaskText = info.subtaskText {
                    Text(subtaskText)
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DragHandleView()
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .opacity(isOverCancelZone ? 0.5 : 1.0)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .scaleEffect(isOverCancelZone ? 0.95 : 1.03)
        .animation(.easeInOut(duration: 0.15), value: isOverCancelZone)
    }
}

#Preview {
    let authService = AuthService()
    FocusTabView(selectedTab: .constant(0))
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
