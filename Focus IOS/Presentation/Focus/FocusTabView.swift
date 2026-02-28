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

// MARK: - Focus Section Anchor Preference

/// Collects anchor bounds from the focus section's first and last rows.
struct FocusSectionBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private enum FocusAddBarFocus: Hashable {
    case task, list, project
}

struct FocusTabView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var viewModel: FocusTabViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @State private var viewMode: FocusViewMode = .focus

    @State private var showScheduleDrawer = false
    @State private var showSettings = false

    // Unified add bar mode
    @State private var addBarMode: TaskType = .task

    // Unified title focus (single @FocusState = atomic transfer = no keyboard flicker)
    @FocusState private var addBarTitleFocus: FocusAddBarFocus?

    // Compact add-task bar state
    @State private var addTaskTitle = ""
    @State private var addTaskSubtasks: [DraftSubtaskEntry] = []
    @State private var addTaskPriority: Priority = .low
    @State private var addTaskCategoryId: UUID? = nil
    @State private var addTaskCategories: [Category] = []
    @State private var addTaskOptionsExpanded = false
    @FocusState private var focusedSubtaskId: UUID?
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false

    // Compact add-list bar state
    @State private var addListTitle = ""
    @State private var addListItems: [DraftSubtaskEntry] = []
    @State private var addListPriority: Priority = .low
    @State private var addListCategoryId: UUID? = nil
    @State private var addListOptionsExpanded = false
    @FocusState private var focusedListItemId: UUID?

    // Compact add-project bar state
    @State private var addProjectTitle = ""
    @State private var addProjectDraftTasks: [DraftTask] = []
    @State private var addProjectPriority: Priority = .low
    @State private var addProjectCategoryId: UUID? = nil
    @State private var addProjectOptionsExpanded = false
    @FocusState private var focusedProjectTaskId: UUID?

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
                    onProfileTap: { showSettings = true }
                )
                Color.clear.frame(height: 0)
                .onChange(of: viewModel.selectedDate) {
                    viewModel.rollupCommitments = []
                    _Concurrency.Task { @MainActor in
                        await viewModel.fetchCommitments()
                    }
                }
                .onChange(of: viewModel.selectedTimeframe) {
                    viewModel.rollupCommitments = []
                    _Concurrency.Task { @MainActor in
                        await viewModel.fetchCommitments()
                    }
                }

                if viewMode == .focus {
                    // MARK: - Focus Mode Content

                    // Fixed "To-Do" title with add button (non-scrollable, daily only)
                    if viewModel.selectedTimeframe == .daily {
                        todoTitleBar
                    }

                    // Content
                    if viewModel.isLoading {
                        ProgressView("Loading...")
                            .frame(maxHeight: .infinity)
                    } else if viewModel.selectedTimeframe == .daily {
                        focusList
                        .backgroundPreferenceValue(FocusSectionBoundsKey.self) { anchors in
                            GeometryReader { proxy in
                                let topAnchor = anchors["top"]
                                let bottomAnchor = anchors["bottom"]
                                // When focus header scrolls off-screen, clamp to top edge
                                let rawTop = topAnchor.map { proxy[$0].minY } ?? 0
                                let containerTop = max(0, rawTop)
                                // When todo header scrolls off-screen, extend container to bottom edge
                                let containerBottom = bottomAnchor.map { proxy[$0].minY + 4 } ?? proxy.size.height
                                let height = containerBottom - containerTop
                                let width = (topAnchor ?? bottomAnchor).map { proxy[$0].width + 4 } ?? (proxy.size.width - 8)
                                // Fade out container as it shrinks, hide when bottom anchor recycled
                                let fadeOpacity = min(1.0, max(0, height / 60.0))
                                if height > 0 && bottomAnchor != nil && fadeOpacity > 0 {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.4 * fadeOpacity))
                                        .frame(width: width, height: max(0, height))
                                        .position(x: proxy.size.width / 2, y: containerTop + max(0, height) / 2)
                                }
                            }
                            .clipped()
                        }
                        .allowsHitTesting(!viewModel.showAddTaskSheet)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [Color.sectionedBackground, Color.sectionedBackground.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 16)
                            .allowsHitTesting(false)
                        }
                    } else {
                        periodFocusList
                        .backgroundPreferenceValue(FocusSectionBoundsKey.self) { anchors in
                            GeometryReader { proxy in
                                let topAnchor = anchors["top"]
                                let bottomAnchor = anchors["bottom"]
                                let rawTop = topAnchor.map { proxy[$0].minY } ?? 0
                                let containerTop = max(0, rawTop)
                                let containerBottom = bottomAnchor.map { proxy[$0].minY + 4 } ?? proxy.size.height
                                let height = containerBottom - containerTop
                                let width = (topAnchor ?? bottomAnchor).map { proxy[$0].width + 4 } ?? (proxy.size.width - 8)
                                let fadeOpacity = min(1.0, max(0, height / 60.0))
                                if height > 0 && bottomAnchor != nil && fadeOpacity > 0 {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.4 * fadeOpacity))
                                        .frame(width: width, height: max(0, height))
                                        .position(x: proxy.size.width / 2, y: containerTop + max(0, height) / 2)
                                }
                            }
                            .clipped()
                        }
                        .allowsHitTesting(!viewModel.showAddTaskSheet)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [Color.sectionedBackground, Color.sectionedBackground.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 16)
                            .allowsHitTesting(false)
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
            .alert(viewModel.errorMessage ?? "", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
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
            .sheet(isPresented: $viewModel.showDayAssignmentSheet) {
                if let commitment = viewModel.selectedCommitmentForDayAssignment {
                    DayAssignmentSheet(commitment: commitment, viewModel: viewModel)
                        .drawerStyle()
                }
            }
            .onChange(of: viewModel.showAddTaskSheet) { _, isShowing in
                if isShowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        switch addBarMode {
                        case .task: addBarTitleFocus = .task
                        case .list: addBarTitleFocus = .list
                        case .project: addBarTitleFocus = .project
                        }
                    }
                }
            }
            .onChange(of: addBarMode) { _, newMode in
                guard viewModel.showAddTaskSheet else { return }
                focusedSubtaskId = nil
                focusedListItemId = nil
                focusedProjectTaskId = nil
                switch newMode {
                case .task: addBarTitleFocus = .task
                case .list: addBarTitleFocus = .list
                case .project: addBarTitleFocus = .project
                }
            }

                // Add-item scrim + bar (unified)
                if viewModel.showAddTaskSheet {
                    // Scrim — visual only, no tap handling
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(50)

                    // All tap handling in one layer
                    VStack(spacing: 0) {
                        // Tap-to-dismiss area
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil
                                )
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dismissActiveAddBar()
                                }
                            }

                        // Floating mode selector + add bar
                        VStack(spacing: 0) {
                            focusAddBarModeSelector
                                .padding(.vertical, 12)

                            focusActiveAddBar
                                .padding(.bottom, 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            } // ZStack
            .background(Color.sectionedBackground.ignoresSafeArea())
        }
    }

    // MARK: - Fixed To-Do Title Bar

    private var todoTitleBar: some View {
        HStack {
            Text("To-Do")
                .font(.golosText(size: 22))
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.addTaskSection = .todo
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.showAddTaskSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.sf(.caption, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.darkGray, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(viewModel.showAddTaskSheet ? 0 : 1)
            .allowsHitTesting(!viewModel.showAddTaskSheet)
        }
        .padding(.horizontal, 42)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    if case .rollupSectionHeader = flat[nextIdx] { return true }
                    if case .rollupDayHeader = flat[nextIdx] { return true }
                    if case .todoPriorityHeader = flat[nextIdx] { return true }
                    return false
                }()
                switch item {
                case .sectionHeader(let section):
                    let isTodoHeader = section == .todo && index > 0
                    sectionHeaderRow(section: section, isTodoHeader: isTodoHeader)

                case .commitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.sectionConfig(for: commitment.section)
                        let focusNum: Int? = commitment.section == .focus ? flat[0..<index].filter {
                            if case .commitment(let c) = $0, c.section == .focus { return true }
                            return false
                        }.count + 1 : nil
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            viewModel: viewModel,
                            fontOverride: commitment.section == .focus ? config.taskFont : nil,
                            verticalPaddingOverride: commitment.section == .focus ? config.verticalPadding : nil,
                            focusNumber: focusNum
                        )
                        .moveDisabled(false)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
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
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }

                case .addSubtaskRow(let parentId, _):
                    InlineAddRow(
                        placeholder: "Subtask",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                        verticalPadding: 6
                    )
                    .padding(.leading, 32)
                    .padding(.trailing, 12)
                    .frame(minHeight: 44)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .addFocusRow:
                    let focusCount = viewModel.uncompletedCommitmentsForSection(.focus).count
                    let isEmpty = focusCount == 0 && viewModel.completedCommitmentsForSection(.focus).isEmpty
                    InlineAddRow(
                        placeholder: "Add focus",
                        buttonLabel: "Add focus",
                        onSubmit: { title in
                            await viewModel.createTaskWithCommitment(title: title, section: .focus)
                        },
                        textFont: .sf(.body, weight: .regular),
                        iconFont: .sf(.body),
                        verticalPadding: 8
                    )
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: isEmpty ? 192 : nil)
                    .moveDisabled(true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .completedCommitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.sectionConfig(for: commitment.section)
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
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
                    }

                case .emptyState(let section):
                    Group {
                        if section == .focus {
                            VStack(spacing: 4) {
                                Text("Nothing to focus on")
                                    .font(.sf(.headline))
                                    .bold()
                                if !viewModel.showAddTaskSheet {
                                    Text("Tap + to add tasks")
                                        .font(.sf(.subheadline))
                                }
                            }
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack {
                                Spacer(minLength: 0)
                                VStack(spacing: 4) {
                                    Text("Nothing to do")
                                        .font(.sf(.headline))
                                        .bold()
                                    if !viewModel.showAddTaskSheet {
                                        Text("Tap + to add tasks")
                                            .font(.sf(.subheadline))
                                    }
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 192 : 240, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.addTaskSection = section
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showAddTaskSheet = true
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .allDoneState:
                    HStack(spacing: 8) {
                        Text("All tasks are completed")
                            .font(.sf(.body, weight: .regular))
                            .foregroundColor(.secondary)
                        Image("CheckCircle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundColor(Color.completedPurple)
                            .scaleEffect(viewModel.allDoneCheckPulse ? 1.35 : 1.0)
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
                        completedCommitments: viewModel.completedCommitmentsForSection(.todo),
                        section: .todo,
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

                case .rollupSectionHeader:
                    RollupSectionHeaderRow(viewModel: viewModel)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                case .rollupDayHeader(let date, let label):
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleRollupGroup(date)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(label.uppercased())
                                .font(.sf(.caption, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.sf(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(viewModel.isRollupGroupExpanded(date) ? 90 : 0))
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isRollupGroupExpanded(date))
                        }
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                case .rollupCommitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            allowBreakdown: false,
                            viewModel: viewModel
                        )
                        .opacity(0.8)
                        .moveDisabled(true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
                    }

                case .todoPriorityHeader(let priority):
                    PrioritySectionHeader(
                        priority: priority,
                        count: viewModel.uncompletedTodoCommitments(for: priority).count,
                        isCollapsed: viewModel.isTodoPriorityCollapsed(priority),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleTodoPriorityCollapsed(priority)
                            }
                        }
                    )
                    .moveDisabled(true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .addTodoTaskRow(let priority):
                    InlineAddRow(
                        placeholder: "Task title",
                        buttonLabel: "Add task",
                        onSubmit: { title in
                            await viewModel.createTaskWithCommitment(title: title, section: .todo, priority: priority)
                        },
                        verticalPadding: 8
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowSeparator(.hidden)

                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }

            // Extra scroll space at the bottom
            Color.clear
                .frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFocusDoneExpanded)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFocusSectionCollapsed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.expandedRollupGroups)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRollupSectionCollapsed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.collapsedTodoPriorities)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchCommitments()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Section Header Row (daily only)

    @ViewBuilder
    private func sectionHeaderRow(section: Section, isTodoHeader: Bool) -> some View {
        if section == .focus {
            FocusSectionHeaderRow(section: section, viewModel: viewModel)
                .anchorPreference(key: FocusSectionBoundsKey.self, value: .bounds) { ["top": $0] }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
        } else if section == .todo {
            Color.clear
                .frame(height: 28)
                .anchorPreference(key: FocusSectionBoundsKey.self, value: .bounds) { ["bottom": $0] }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } else {
            FocusSectionHeaderRow(section: section, viewModel: viewModel)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: isTodoHeader ? 20 : 8, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Period Focus List (week / month / year)

    private var periodFocusList: some View {
        let flat = viewModel.flattenedDisplayItems
        return List {
            ForEach(Array(flat.enumerated()), id: \.element.id) { index, item in
                let nextIsSection: Bool = {
                    let nextIdx = index + 1
                    if nextIdx >= flat.count { return true }
                    if case .sectionHeader = flat[nextIdx] { return true }
                    if case .rollupSectionHeader = flat[nextIdx] { return true }
                    if case .rollupDayHeader = flat[nextIdx] { return true }
                    return false
                }()
                switch item {
                case .sectionHeader(let section):
                    periodSectionHeaderRow(section: section, index: index)

                case .commitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.sectionConfig(for: commitment.section)
                        let focusNum: Int? = commitment.section == .focus ? flat[0..<index].filter {
                            if case .commitment(let c) = $0, c.section == .focus { return true }
                            return false
                        }.count + 1 : nil
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            viewModel: viewModel,
                            fontOverride: commitment.section == .focus ? config.taskFont : nil,
                            verticalPaddingOverride: commitment.section == .focus ? config.verticalPadding : nil,
                            focusNumber: focusNum
                        )
                        .moveDisabled(false)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
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
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }

                case .addSubtaskRow(let parentId, _):
                    InlineAddRow(
                        placeholder: "Subtask",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                        verticalPadding: 6
                    )
                    .padding(.leading, 32)
                    .padding(.trailing, 12)
                    .frame(minHeight: 44)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .addFocusRow:
                    let focusCount = viewModel.uncompletedCommitmentsForSection(.focus).count
                    let isEmpty = focusCount == 0 && viewModel.completedCommitmentsForSection(.focus).isEmpty
                    InlineAddRow(
                        placeholder: "Add focus",
                        buttonLabel: "Add focus",
                        onSubmit: { title in
                            await viewModel.createTaskWithCommitment(title: title, section: .focus)
                        },
                        textFont: .sf(.body, weight: .regular),
                        iconFont: .sf(.body),
                        verticalPadding: 8
                    )
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: isEmpty ? 192 : nil)
                    .moveDisabled(true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .completedCommitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        let config = viewModel.sectionConfig(for: commitment.section)
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
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
                    }

                case .emptyState(let section):
                    Group {
                        if section == .focus {
                            VStack(spacing: 4) {
                                Text("Nothing to focus on")
                                    .font(.sf(.headline))
                                    .bold()
                                if !viewModel.showAddTaskSheet {
                                    Text("Tap + to add tasks")
                                        .font(.sf(.subheadline))
                                }
                            }
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack {
                                Spacer(minLength: 0)
                                VStack(spacing: 4) {
                                    Text("Nothing to do")
                                        .font(.sf(.headline))
                                        .bold()
                                    if !viewModel.showAddTaskSheet {
                                        Text("Tap + to add tasks")
                                            .font(.sf(.subheadline))
                                    }
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 192 : 240, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.addTaskSection = section
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showAddTaskSheet = true
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                case .allDoneState:
                    HStack(spacing: 8) {
                        Text("All tasks are completed")
                            .font(.sf(.body, weight: .regular))
                            .foregroundColor(.secondary)
                        Image("CheckCircle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundColor(Color.completedPurple)
                            .scaleEffect(viewModel.allDoneCheckPulse ? 1.35 : 1.0)
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
                        completedCommitments: viewModel.completedCommitmentsForSection(.todo),
                        section: .todo,
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

                case .rollupSectionHeader:
                    RollupSectionHeaderRow(viewModel: viewModel)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                case .rollupDayHeader(let date, let label):
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleRollupGroup(date)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(label.uppercased())
                                .font(.sf(.caption, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.sf(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(viewModel.isRollupGroupExpanded(date) ? 90 : 0))
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isRollupGroupExpanded(date))
                        }
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                case .rollupCommitment(let commitment):
                    if let task = viewModel.tasksMap[commitment.taskId] {
                        CommitmentRow(
                            commitment: commitment,
                            task: task,
                            section: commitment.section,
                            allowBreakdown: false,
                            viewModel: viewModel
                        )
                        .opacity(0.8)
                        .moveDisabled(true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(nextIsSection ? .hidden : .visible)
                        .listRowSeparatorTint(Color.secondary.opacity(0.2))
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 4 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 4 }
                    }

                // Daily-only items — should not appear in period data, but handle gracefully
                case .todoPriorityHeader, .addTodoTaskRow:
                    EmptyView()
                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }

            // Extra scroll space at the bottom
            Color.clear
                .frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFocusDoneExpanded)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFocusSectionCollapsed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.expandedRollupGroups)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRollupSectionCollapsed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTodoSectionCollapsed)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchCommitments()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Period Section Header Row (week / month / year)

    @ViewBuilder
    private func periodSectionHeaderRow(section: Section, index: Int) -> some View {
        if section == .focus {
            FocusSectionHeaderRow(section: section, viewModel: viewModel)
                .anchorPreference(key: FocusSectionBoundsKey.self, value: .bounds) { ["top": $0] }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
        } else if section == .todo {
            VStack(spacing: 0) {
                // Invisible anchor for the focus container bottom edge
                Color.clear
                    .frame(height: 0)
                    .anchorPreference(key: FocusSectionBoundsKey.self, value: .bounds) { ["bottom": $0] }

                HStack {
                    HStack(spacing: 8) {
                        Text("Unassigned Tasks")
                            .font(.golosText(size: 22))
                        Image(systemName: "chevron.right")
                            .font(.sf(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(viewModel.isTodoSectionCollapsed ? 0 : 90))
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isTodoSectionCollapsed)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isTodoSectionCollapsed.toggle()
                        }
                    }
                    Spacer()
                    if !viewModel.isTodoSectionCollapsed {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.addTaskSection = .todo
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.showAddTaskSheet = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.sf(.caption, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.darkGray, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(viewModel.showAddTaskSheet ? 0 : 1)
                        .allowsHitTesting(!viewModel.showAddTaskSheet)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 28)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
            .listRowSeparator(.hidden)
        } else {
            FocusSectionHeaderRow(section: section, viewModel: viewModel)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: index > 0 ? 20 : 8, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Add Bar Mode Selector

    private var focusAddBarModeSelector: some View {
        HStack(spacing: 12) {
            focusAddBarModeCircle(mode: .task, icon: "checklist")
            focusAddBarModeCircle(mode: .list, icon: "list.bullet")
            focusAddBarModeCircle(mode: .project, icon: "folder")
            Spacer()
        }
        .padding(.horizontal)
    }

    private func focusAddBarModeCircle(mode: TaskType, icon: String) -> some View {
        let isActive = addBarMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                addBarMode = mode
            }
        } label: {
            Image(systemName: isActive && mode == .project ? "folder.fill" : icon)
                .font(.sf(.body, weight: .medium))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 36, height: 36)
                .glassEffect(
                    isActive
                        ? .regular.tint(.black).interactive()
                        : .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var focusActiveAddBar: some View {
        switch addBarMode {
        case .task: focusAddTaskBar
        case .list: focusAddListBar
        case .project: focusAddProjectBar
        }
    }

    // MARK: - Pre-computed title emptiness

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddListTitleEmpty: Bool {
        addListTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddProjectTitleEmpty: Bool {
        addProjectTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Compact Add Task Bar

    private var focusAddTaskBar: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Create a new task", text: $addTaskTitle)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .task)
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

            // Sub-task row: [+ Sub-task] [...] Spacer [AI Breakdown] [Checkmark]
            HStack(spacing: 8) {
                // Add sub-task button
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
                    .padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // More options pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sf(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // AI Breakdown
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
                                .foregroundColor(!isAddTaskTitleEmpty ? .blue : .primary)
                        }
                        Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                            .font(.sf(.caption, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        !isAddTaskTitleEmpty ? Color.white : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

                // Submit button (checkmark)
                Button {
                    saveCompactTask()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddTaskTitleEmpty ? Color(.systemGray4) : Color.appRed,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddTaskTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Bottom row: [Category] [Priority] — toggled by ellipsis
            if addTaskOptionsExpanded {
                HStack(spacing: 8) {
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
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

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
                            Circle()
                                .fill(addTaskPriority.dotColor)
                                .frame(width: 8, height: 8)
                            Text(addTaskPriority.displayName)
                                .font(.sf(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }

            Spacer().frame(height: 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .onAppear { fetchCategories() }
    }

    // MARK: - Compact Add List Bar

    private var focusAddListBar: some View {
        VStack(spacing: 0) {
            // List title row
            TextField("Create a new list", text: $addListTitle)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .list)
                .submitLabel(.return)
                .onSubmit {
                    saveFocusList()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Items (expand when present)
            DraftSubtaskListEditor(
                subtasks: $addListItems,
                focusedSubtaskId: $focusedListItemId,
                onAddNew: { addNewListItem() },
                placeholder: "Item"
            )

            // Row 1: [Item] [...] Spacer [Checkmark]
            HStack(spacing: 8) {
                Button {
                    addNewListItem()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.sf(.caption))
                        Text("Item")
                            .font(.sf(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // More options pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sf(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Submit button (checkmark)
                Button {
                    saveFocusList()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(isAddListTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddListTitleEmpty ? Color(.systemGray4) : Color.appRed,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddListTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Row 2: [Category] [Priority] — toggled by ellipsis
            if addListOptionsExpanded {
                HStack(spacing: 8) {
                    // Category pill
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
                        ForEach(addTaskCategories) { category in
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
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.sf(.caption))
                            Text(LocalizedStringKey(addListCategoryPillLabel))
                                .font(.sf(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    // Priority pill
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
                        HStack(spacing: 4) {
                            Circle()
                                .fill(addListPriority.dotColor)
                                .frame(width: 8, height: 8)
                            Text(addListPriority.displayName)
                                .font(.sf(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }

            Spacer().frame(height: 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .onAppear { fetchCategories() }
    }

    // MARK: - Compact Add Project Bar

    private var focusAddProjectBar: some View {
        VStack(spacing: 0) {
            // Project title row
            TextField("Create a new project", text: $addProjectTitle)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .project)
                .submitLabel(.return)
                .onSubmit {
                    saveFocusProject()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Tasks + subtasks area
            if !addProjectDraftTasks.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(addProjectDraftTasks) { task in
                        focusProjectTaskDraftRow(task: task)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            // Row 1: [Task] [...] Spacer [Checkmark]
            HStack(spacing: 8) {
                Button {
                    addNewProjectTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.sf(.caption))
                        Text("Task")
                            .font(.sf(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // More options pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectOptionsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sf(.caption, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Submit button (checkmark)
                Button {
                    saveFocusProject()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(isAddProjectTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddProjectTitleEmpty ? Color(.systemGray4) : Color.appRed,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddProjectTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Row 2: [Category] [Priority] — toggled by ellipsis
            if addProjectOptionsExpanded {
                HStack(spacing: 8) {
                    // Category pill
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
                        ForEach(addTaskCategories) { category in
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
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.sf(.caption))
                            Text(LocalizedStringKey(addProjectCategoryPillLabel))
                                .font(.sf(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    // Priority pill
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
                        HStack(spacing: 4) {
                            Circle()
                                .fill(addProjectPriority.dotColor)
                                .frame(width: 8, height: 8)
                            Text(addProjectPriority.displayName)
                                .font(.sf(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }

            Spacer().frame(height: 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .onAppear { fetchCategories() }
    }

    // MARK: - Project Task Draft Row

    @ViewBuilder
    private func focusProjectTaskDraftRow(task: DraftTask) -> some View {
        // Task row
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.sf(.caption2))
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: focusProjectTaskBinding(for: task.id), axis: .vertical)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($focusedProjectTaskId, equals: task.id)
                .lineLimit(1...3)
                .onChange(of: focusProjectTaskBinding(for: task.id).wrappedValue) { _, newValue in
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
                    .font(.sf(.caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.sf(.caption2))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Sub-task", text: focusProjectSubtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.sf(.body))
                    .textFieldStyle(.plain)
                    .focused($focusedProjectTaskId, equals: subtask.id)
                    .lineLimit(1...3)
                    .onChange(of: focusProjectSubtaskBinding(forSubtask: subtask.id, inTask: task.id).wrappedValue) { _, newValue in
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
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .padding(.top, 12)

        // "+ Sub-task" button
        Button {
            addNewProjectSubtask(toTask: task.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.sf(.subheadline))
                Text("Sub-task")
                    .font(.sf(.subheadline))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Task Helpers

    private func saveCompactTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let section = viewModel.addTaskSection
        let priority = addTaskPriority
        let categoryId = addTaskCategoryId

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Transfer focus to title BEFORE removing subtask fields to prevent keyboard bounce
        addBarTitleFocus = .task
        focusedSubtaskId = nil

        // Clear fields immediately for rapid entry
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskPriority = .low
        addTaskCategoryId = nil
        addTaskOptionsExpanded = false
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await viewModel.createTaskWithSubtasks(title: title, section: section, subtaskTitles: subtasksToCreate, priority: priority, categoryId: categoryId)
        }
    }

    private func addNewSubtask() {
        addBarTitleFocus = .task
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
                    let manualSubtasks = addTaskSubtasks.filter { !$0.isAISuggested }
                    addTaskSubtasks = manualSubtasks + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail
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
        addTaskOptionsExpanded = false
        hasGeneratedBreakdown = false
        addBarTitleFocus = nil
        focusedSubtaskId = nil
    }

    // MARK: - List Helpers

    private var addListCategoryPillLabel: String {
        if let categoryId = addListCategoryId,
           let category = addTaskCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveFocusList() {
        let title = addListTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let itemTitles = addListItems
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let section = viewModel.addTaskSection
        let priority = addListPriority
        let categoryId = addListCategoryId

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        addBarTitleFocus = .list
        focusedListItemId = nil

        addListTitle = ""
        addListItems = []
        addListPriority = .low
        addListCategoryId = nil
        addListOptionsExpanded = false

        _Concurrency.Task { @MainActor in
            await viewModel.createListWithCommitment(title: title, section: section, itemTitles: itemTitles, priority: priority, categoryId: categoryId)
        }
    }

    private func addNewListItem() {
        addBarTitleFocus = .list
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addListItems.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedListItemId = newEntry.id
        }
    }

    private func dismissAddList() {
        addListTitle = ""
        addListItems = []
        addListPriority = .low
        addListCategoryId = nil
        addListOptionsExpanded = false
        addBarTitleFocus = nil
        focusedListItemId = nil
    }

    // MARK: - Project Helpers

    private var addProjectCategoryPillLabel: String {
        if let categoryId = addProjectCategoryId,
           let category = addTaskCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveFocusProject() {
        let title = addProjectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let draftTasks = addProjectDraftTasks.filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let section = viewModel.addTaskSection
        let priority = addProjectPriority
        let categoryId = addProjectCategoryId

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        addBarTitleFocus = .project
        focusedProjectTaskId = nil

        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectPriority = .low
        addProjectCategoryId = nil
        addProjectOptionsExpanded = false

        _Concurrency.Task { @MainActor in
            await viewModel.createProjectWithCommitment(title: title, section: section, draftTasks: draftTasks, priority: priority, categoryId: categoryId)
        }
    }

    private func focusProjectTaskBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: { addProjectDraftTasks.first(where: { $0.id == taskId })?.title ?? "" },
            set: { newValue in
                if let idx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) {
                    addProjectDraftTasks[idx].title = newValue
                }
            }
        )
    }

    private func focusProjectSubtaskBinding(forSubtask subtaskId: UUID, inTask taskId: UUID) -> Binding<String> {
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
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks.append(newTask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newTask.id
        }
    }

    private func addNewProjectSubtask(toTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let newSubtask = DraftSubtask(title: "")
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks[tIdx].subtasks.append(newSubtask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newSubtask.id
        }
    }

    private func removeProjectTask(id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks.removeAll { $0.id == id }
        }
    }

    private func removeProjectSubtask(id: UUID, fromTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks[tIdx].subtasks.removeAll { $0.id == id }
        }
    }

    private func dismissAddProject() {
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectPriority = .low
        addProjectCategoryId = nil
        addProjectOptionsExpanded = false
        addBarTitleFocus = nil
        focusedProjectTaskId = nil
    }

    // MARK: - Shared Dismiss

    private func dismissActiveAddBar() {
        dismissAddTask()
        dismissAddList()
        dismissAddProject()
        viewModel.showAddTaskSheet = false
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

    private var sectionConfig: FocusSectionConfig {
        viewModel.sectionConfig(for: section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(title)
                    .font(.golosText(size: 22))

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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showAddTaskSheet = true
                        }
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
                        Text("Focus")
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
                if section == .todo {
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
                    // Empty state centered in the focus zone
                    VStack {
                        Spacer(minLength: 0)
                        Group {
                            if section == .focus {
                                VStack(spacing: 4) {
                                    Text("Nothing to focus on")
                                        .font(.sf(.headline))
                                        .bold()
                                    if !viewModel.showAddTaskSheet {
                                        Text("Tap + to start")
                                            .font(.sf(.subheadline))
                                    }
                                }
                                .foregroundColor(.secondary)
                            } else {
                                Text("No task yet. Tap + to add one.")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 180 : nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.addTaskSection = section
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showAddTaskSheet = true
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        // Centering zone for uncompleted tasks
                        VStack(spacing: 0) {
                            if section == .focus && sectionConfig.containerMinHeight > 0 {
                                Spacer(minLength: 0)
                            }

                            if uncompletedCommitments.isEmpty && !completedCommitments.isEmpty && section == .focus {
                                // All-done state
                                HStack(spacing: 8) {
                                    Text("All tasks are completed")
                                        .font(.sf(.title3, weight: .regular))
                                        .foregroundColor(.secondary)
                                    Image("CheckCircle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 34, height: 34)
                                        .foregroundColor(Color.completedPurple)
                                        .scaleEffect(viewModel.allDoneCheckPulse ? 1.35 : 1.0)
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
                                                fontOverride: section == .focus ? sectionConfig.taskFont : nil,
                                                verticalPaddingOverride: section == .focus ? sectionConfig.verticalPadding : nil,
                                                focusNumber: section == .focus ? index + 1 : nil
                                            )
                                        }
                                    }
                                }
                            }

                            if section == .focus && sectionConfig.containerMinHeight > 0 {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(minHeight: sectionConfig.containerMinHeight > 0 ? sectionConfig.containerMinHeight : nil)

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
                                        fontOverride: sectionConfig.completedTaskFont,
                                        verticalPaddingOverride: sectionConfig.completedVerticalPadding
                                    )
                                    .opacity(sectionConfig.completedOpacity)
                                }
                            }
                        }

                        if section == .todo && !completedCommitments.isEmpty {
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
            HStack(spacing: 8) {
                Button {
                    viewModel.toggleDoneSubsectionCollapsed()
                } label: {
                    HStack(spacing: 4) {
                        Text("Completed")
                            .font(.sf(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("\(completedCommitments.count)")
                            .font(.sf(size: 12))
                            .foregroundColor(.secondary)

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.sf(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.vertical, 10)

            // Expanded completed tasks
            if isExpanded {
                let config = viewModel.sectionConfig(for: section)
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
            if section == .focus {
                // Focus section: pill-style header matching priority level design
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.completedPurple)
                                .frame(width: 22, height: 22)
                            Image("PushPin")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                        }

                        Text(section.displayName)
                            .font(.golosText(size: 14))

                        if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                            Text("\(sectionCommitments.count)/\(maxTasks)")
                                .font(.sf(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.sf(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(viewModel.isSectionCollapsed(section) ? 0 : 90))
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isSectionCollapsed(section))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                    )

                    Spacer()
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleSectionCollapsed(section)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 0)
                .padding(.horizontal, 12)
            } else {
                // Non-focus sections: invisible divider (matches background)
                Rectangle()
                    .fill(Color.sectionedBackground)
                    .frame(height: 1)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Rollup Section Header Row

struct RollupSectionHeaderRow: View {
    @ObservedObject var viewModel: FocusTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text(viewModel.overviewSectionTitle)
                        .font(.golosText(size: 22))
                    Image(systemName: "chevron.right")
                        .font(.sf(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(viewModel.isRollupSectionCollapsed ? 0 : 90))
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isRollupSectionCollapsed)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleRollupSection()
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Commitment Row

struct CommitmentRow: View {
    let commitment: Commitment
    let task: FocusTask
    let section: Section
    var allowBreakdown: Bool = true
    @ObservedObject var viewModel: FocusTabViewModel
    var fontOverride: Font? = nil
    var verticalPaddingOverride: CGFloat? = nil
    var focusNumber: Int? = nil
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

    /// Can break down if: not daily AND breakdown is allowed in this context (hidden on rollup rows)
    /// Temporarily disabled — feature kept but not accessible from UI
    private var canBreakdown: Bool { false }

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

                // Focus number
                if let number = focusNumber {
                    Text("\(number)")
                        .font(fontOverride ?? .sf(.body, weight: .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(fontOverride ?? .sf(.body, weight: .regular))
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
                .frame(maxWidth: .infinity, minHeight: section == .focus || section == .todo ? 36 : nil, alignment: .leading)
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

                    if commitment.timeframe != .daily, !task.isCompleted {
                        ContextMenuItems.assignButton {
                            viewModel.selectedCommitmentForDayAssignment = commitment
                            viewModel.showDayAssignmentSheet = true
                        }
                    }

                    if section == .todo, !task.isCompleted {
                        ContextMenuItems.prioritySubmenu(
                            currentPriority: task.priority
                        ) { priority in
                            _Concurrency.Task {
                                await viewModel.updateTaskPriority(task, priority: priority)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        _Concurrency.Task { @MainActor in
                            await viewModel.removeCommitment(commitment)
                        }
                    } label: {
                        Label(commitment.timeframe.unscheduleLabel, systemImage: "minus.circle")
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
                            Label("Push to \(commitment.timeframe.nextTimeframeLabel)", systemImage: "arrow.right")
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
                    Label("Unschedule", systemImage: "minus.circle")
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
    /// Temporarily disabled — feature kept but not accessible from UI
    private var canBreakdown: Bool { false }

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
