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

// MARK: - Section Frame Preference Key

struct SectionFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Drawer Top Preference Key

struct DrawerTopPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FocusTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var viewModel: FocusTabViewModel
    @State private var showCalendarPicker = false
    @State private var viewMode: FocusViewMode = .focus

    // Drag state
    @State private var draggingCommitmentId: UUID?
    @State private var dragFingerY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var dragReorderAdjustment: CGFloat = 0
    @State private var lastReorderTime: Date = .distantPast
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var sectionFrames: [String: CGRect] = [:]
    @State private var targetedSection: Section?
    @State private var showScheduleDrawer = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date Navigator with integrated timeframe picker and pill row
                DateNavigator(
                    selectedDate: $viewModel.selectedDate,
                    selectedTimeframe: $viewModel.selectedTimeframe,
                    viewMode: $viewMode,
                    compact: viewMode == .schedule,
                    onCalendarTap: { showCalendarPicker = true }
                )
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
                        ScrollView {
                            VStack(spacing: 20) {
                                // Focus Section
                                SectionView(
                                    title: "Focus",
                                    section: .focus,
                                    viewModel: viewModel,
                                    draggingCommitmentId: draggingCommitmentId,
                                    dragTranslation: dragTranslation,
                                    dragReorderAdjustment: dragReorderAdjustment,
                                    targetedSection: targetedSection,
                                    onDragChanged: { id, value in handleCommitmentDrag(id, value) },
                                    onDragEnded: { handleCommitmentDragEnd() }
                                )
                                .zIndex(draggingCommitmentId != nil && viewModel.uncompletedCommitmentsForSection(.focus).contains(where: { $0.id == draggingCommitmentId }) ? 1 : 0)

                                // Extra Section
                                SectionView(
                                    title: "Extra",
                                    section: .extra,
                                    viewModel: viewModel,
                                    draggingCommitmentId: draggingCommitmentId,
                                    dragTranslation: dragTranslation,
                                    dragReorderAdjustment: dragReorderAdjustment,
                                    targetedSection: targetedSection,
                                    onDragChanged: { id, value in handleCommitmentDrag(id, value) },
                                    onDragEnded: { handleCommitmentDragEnd() }
                                )
                                .zIndex(draggingCommitmentId != nil && viewModel.uncompletedCommitmentsForSection(.extra).contains(where: { $0.id == draggingCommitmentId }) ? 1 : 0)
                            }
                            .padding()
                            .onPreferenceChange(RowFramePreference.self) { frames in
                                rowFrames = frames
                            }
                            .onPreferenceChange(SectionFramePreference.self) { frames in
                                sectionFrames = frames
                            }
                        }
                        .coordinateSpace(name: "focusList")
                        .refreshable {
                            await withCheckedContinuation { continuation in
                                _Concurrency.Task { @MainActor in
                                    await viewModel.fetchCommitments()
                                    continuation.resume()
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
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .frame(width: 56, height: 56)
                                                .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
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
            .animation(.easeInOut(duration: 0.25), value: showScheduleDrawer)
            .animation(.easeInOut(duration: 0.25), value: viewModel.timelineVM.isDrawerRetractedForDrag)
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
            .sheet(isPresented: $showCalendarPicker) {
                SingleSelectCalendarPicker(
                    selectedDate: $viewModel.selectedDate,
                    timeframe: viewModel.selectedTimeframe
                )
                .drawerStyle()
            }
            .sheet(isPresented: $viewModel.showAddTaskSheet) {
                AddTaskToFocusSheet(
                    section: viewModel.addTaskSection,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Drag Handlers

    private func handleCommitmentDrag(_ commitmentId: UUID, _ value: DragGesture.Value) {
        if draggingCommitmentId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingCommitmentId = commitmentId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        // Update targeted section highlight
        if let draggedCommitment = viewModel.commitments.first(where: { $0.id == commitmentId }) {
            let otherSection: Section = draggedCommitment.section == .focus ? .extra : .focus
            if let sectionFrame = sectionFrames[otherSection.rawValue],
               dragFingerY >= sectionFrame.minY && dragFingerY <= sectionFrame.maxY {
                if targetedSection != otherSection {
                    targetedSection = otherSection
                }
            } else {
                if targetedSection != nil {
                    targetedSection = nil
                }
            }
        }

        // Cooldown: prevent double-swaps during animation
        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        // Find the dragged commitment and its current section
        guard let draggedCommitment = viewModel.commitments.first(where: { $0.id == commitmentId }) else { return }

        // Within-section reorder: check midpoint crossings in same section
        let sameSection = viewModel.uncompletedCommitmentsForSection(draggedCommitment.section)
        guard let currentIdx = sameSection.firstIndex(where: { $0.id == commitmentId }) else { return }

        for (idx, other) in sameSection.enumerated() where other.id != commitmentId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderCommitment(droppedId: commitmentId, targetId: other.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleCommitmentDragEnd() {
        // Check for cross-section drop
        if let commitmentId = draggingCommitmentId,
           let commitment = viewModel.commitments.first(where: { $0.id == commitmentId }) {
            let otherSection: Section = commitment.section == .focus ? .extra : .focus
            let otherSectionKey = otherSection.rawValue

            if let sectionFrame = sectionFrames[otherSectionKey],
               dragFingerY >= sectionFrame.minY && dragFingerY <= sectionFrame.maxY {
                // Validate Focus section capacity
                if otherSection != .focus || viewModel.canAddTask(to: .focus, timeframe: commitment.timeframe, date: commitment.commitmentDate) {
                    // Find insertion index based on finger position
                    let otherList = viewModel.uncompletedCommitmentsForSection(otherSection)
                    var insertIdx = otherList.count
                    for (idx, other) in otherList.enumerated() {
                        if let frame = rowFrames[other.id], dragFingerY < frame.midY {
                            insertIdx = idx
                            break
                        }
                    }
                    viewModel.moveCommitmentToSectionAtIndex(commitment, to: otherSection, atIndex: insertIdx)
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            draggingCommitmentId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
            targetedSection = nil
        }
        lastReorderTime = .distantPast
    }
}

// MARK: - Focus Section Config

private struct FocusSectionConfig {
    let taskFont: Font
    let verticalPadding: CGFloat
    let containerMinHeight: CGFloat
    let completedTaskFont: Font
    let completedVerticalPadding: CGFloat
    let completedOpacity: Double
}

// MARK: - Section View

struct SectionView: View {
    let title: String
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel

    // Drag parameters from parent
    var draggingCommitmentId: UUID?
    var dragTranslation: CGFloat = 0
    var dragReorderAdjustment: CGFloat = 0
    var targetedSection: Section? = nil
    var onDragChanged: ((UUID, DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

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
        guard section == .focus else {
            return FocusSectionConfig(
                taskFont: .body,
                verticalPadding: 8,
                containerMinHeight: 0,
                completedTaskFont: .body,
                completedVerticalPadding: 6,
                completedOpacity: 0.5
            )
        }

        // Yearly supports up to 10 tasks — use compact layout, no scaling
        guard viewModel.selectedTimeframe != .yearly else {
            return FocusSectionConfig(
                taskFont: .body,
                verticalPadding: 10,
                containerMinHeight: 0,
                completedTaskFont: .footnote,
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        }

        let count = uncompletedCommitments.count
        switch count {
        case 0, 1:
            return FocusSectionConfig(
                taskFont: .title,
                verticalPadding: 24,
                containerMinHeight: 150,
                completedTaskFont: .subheadline,
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        case 2:
            return FocusSectionConfig(
                taskFont: .title2,
                verticalPadding: 18,
                containerMinHeight: 150,
                completedTaskFont: .subheadline,
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        default:
            return FocusSectionConfig(
                taskFont: .title3,
                verticalPadding: 14,
                containerMinHeight: 0,
                completedTaskFont: .subheadline,
                completedVerticalPadding: 6,
                completedOpacity: 0.45
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 12) {
                // Section icon
                Image(systemName: section == .focus ? "target" : "tray.full")
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                // Count display
                if let maxTasks = section.maxTasks(for: viewModel.selectedTimeframe) {
                    Text("\(sectionCommitments.count)/\(maxTasks)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if !sectionCommitments.isEmpty {
                    Text("\(sectionCommitments.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Collapse chevron (Extra section only) - next to title/count
                if section == .extra {
                    Image(systemName: viewModel.isSectionCollapsed(section) ? "chevron.right" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Add button (far right)
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
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCapacityPopover) {
                    let current = viewModel.taskCount(for: .focus)
                    let max = Section.focus.maxTasks(for: viewModel.selectedTimeframe) ?? 0
                    VStack(spacing: 4) {
                        Text("Focus section")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Section full")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(current)/\(max)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if section == .extra {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleSectionCollapsed(section)
                    }
                }
            }

            // Committed Tasks (hidden when collapsed)
            if !viewModel.isSectionCollapsed(section) {
                if sectionCommitments.isEmpty && completedCommitments.isEmpty {
                    // Empty state centered in the focus zone
                    VStack {
                        Spacer(minLength: 0)
                        Text("No task yet. Tap + to add one.")
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: section == .focus ? 180 : nil)
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
                                        .font(.largeTitle)
                                        .foregroundColor(.green.opacity(0.6))
                                    Text("All done!")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                // Uncompleted commitments — draggable with floating pill
                                ForEach(Array(uncompletedCommitments.enumerated()), id: \.element.id) { index, commitment in
                                    if let task = viewModel.tasksMap[commitment.taskId] {
                                        let isDragging = draggingCommitmentId == commitment.id

                                        VStack(spacing: 0) {
                                            if index > 0 {
                                                Divider()
                                            }
                                            CommitmentRow(
                                                commitment: commitment,
                                                task: task,
                                                section: section,
                                                viewModel: viewModel,
                                                onDragChanged: { value in onDragChanged?(commitment.id, value) },
                                                onDragEnded: { onDragEnded?() },
                                                fontOverride: section == .focus ? focusConfig.taskFont : nil,
                                                verticalPaddingOverride: section == .focus ? focusConfig.verticalPadding : nil
                                            )
                                        }
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: RowFramePreference.self,
                                                    value: [commitment.id: geo.frame(in: .named("focusList"))]
                                                )
                                            }
                                        )
                                        .background(
                                            isDragging
                                                ? AnyShapeStyle(.regularMaterial)
                                                : AnyShapeStyle(.clear),
                                            in: .rect(cornerRadius: 10)
                                        )
                                        .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                                        .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                                        .scaleEffect(isDragging ? 1.03 : 1.0)
                                        .zIndex(isDragging ? 1 : 0)
                                        .transaction { t in
                                            if isDragging { t.animation = nil }
                                        }
                                    }
                                }
                            }

                            if section == .focus && focusConfig.containerMinHeight > 0 {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(minHeight: focusConfig.containerMinHeight > 0 ? focusConfig.containerMinHeight : nil)
                        .animation(.easeInOut(duration: 0.3), value: uncompletedCommitments.count)

                        // Completed commitments — below the centering zone for Focus, Done pill for Extra
                        if section == .focus && !completedCommitments.isEmpty {
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
        .padding(.vertical)
        .padding(.horizontal, 8)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(targetedSection == section ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionFramePreference.self,
                    value: [section.rawValue: geo.frame(in: .named("focusList"))]
                )
            }
        )
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
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("(\(completedCommitments.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded completed tasks
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(completedCommitments.enumerated()), id: \.element.id) { index, commitment in
                        if let task = viewModel.tasksMap[commitment.taskId] {
                            Divider()
                            CommitmentRow(commitment: commitment, task: task, section: section, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Add Task Sheet

struct AddTaskToFocusSheet: View {
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var taskTitle = ""
    @State private var draftSubtasks: [DraftSubtaskEntry] = []
    @State private var hasScheduledTime = false
    @State private var scheduledTime: Date = {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundUp = ((minute / 15) + 1) * 15
        return calendar.date(byAdding: .minute, value: roundUp - minute, to: now) ?? now
    }()
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Task title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Task")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        TextField("What do you need to do?", text: $taskTitle)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }

                    // Subtasks
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subtasks")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        ForEach(Array(draftSubtasks.enumerated()), id: \.element.id) { index, _ in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.5))

                                TextField("Subtask", text: $draftSubtasks[index].title)
                                    .font(.subheadline)

                                Button {
                                    draftSubtasks.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 4)
                        }

                        Button {
                            draftSubtasks.append(DraftSubtaskEntry())
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                Text("Add subtask")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }

                    // Schedule time toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $hasScheduledTime) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                                Text("Schedule time")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .tint(.blue)

                        if hasScheduledTime {
                            DatePicker(
                                "Time",
                                selection: $scheduledTime,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }

                    // Add Task button
                    Button {
                        saveTask()
                    } label: {
                        Text("Add Task")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.blue.opacity(0.5)
                                          : Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                titleFocused = true
            }
        }
    }

    private func saveTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = draftSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let shouldSchedule = hasScheduledTime
        let timeToSchedule = scheduledTime

        _Concurrency.Task { @MainActor in
            guard let result = await viewModel.createTaskWithCommitment(title: title, section: section) else {
                return
            }

            for subtaskTitle in subtasksToCreate {
                await viewModel.createSubtask(title: subtaskTitle, parentId: result.taskId, parentCommitment: result.commitment)
            }

            if shouldSchedule {
                await viewModel.timelineVM.scheduleCommitmentTime(result.commitment.id, at: timeToSchedule)
            }

            dismiss()
        }
    }
}

// MARK: - Commitment Row

struct CommitmentRow: View {
    let commitment: Commitment
    let task: FocusTask
    let section: Section
    @ObservedObject var viewModel: FocusTabViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var fontOverride: Font? = nil
    var verticalPaddingOverride: CGFloat? = nil

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
            // Main task row - matching ExpandableTaskRow style
            HStack(spacing: 12) {
                // Drag handle (left side) - only for uncompleted tasks with drag enabled
                if !task.isCompleted && onDragChanged != nil {
                    DragHandleView()
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 5, coordinateSpace: .named("focusList"))
                                .onChanged { value in onDragChanged?(value) }
                                .onEnded { _ in onDragEnded?() }
                        )
                }

                // Child commitment indicator (indentation)
                if commitment.isChildCommitment {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(fontOverride ?? (section == .focus ? .title3 : .body))
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                        if task.type == .list {
                            Image(systemName: "list.bullet")
                                .font(fontOverride != nil ? .subheadline : (section == .focus ? .subheadline : .caption))
                                .foregroundColor(.blue)
                        }
                    }

                    // Subtask count indicator
                    if hasSubtasks {
                        let completedCount = subtasks.filter { $0.isCompleted }.count
                        Text("\(completedCount)/\(subtasks.count) subtasks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Child commitment count indicator
                    if childCount > 0 {
                        Text("\(childCount) broken down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleExpanded(task.id)
                    }
                }
                .onLongPressGesture {
                    viewModel.selectedTaskForDetails = task
                }

                // Commit button (for non-daily commitments)
                if canBreakdown {
                    Button {
                        viewModel.selectedCommitmentForCommit = commitment
                        viewModel.showCommitSheet = true
                    } label: {
                        Image(systemName: "arrow.down.forward.circle")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

                // Completion button (right side for thumb access)
                Button {
                    Task {
                        await viewModel.toggleTaskCompletion(task)
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, verticalPaddingOverride ?? (section == .focus ? 14 : 8))
            .padding(.leading, 8)
            .padding(.trailing, 12)

            // Subtasks and add row (shown when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                        FocusSubtaskRow(subtask: subtask, parentId: task.id, parentCommitment: commitment, viewModel: viewModel)

                        if index < subtasks.count - 1 {
                            Divider()
                        }
                    }
                    Divider()
                    FocusInlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                }
                .padding(.leading, 32)
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
                .font(.subheadline)
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
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Checkbox on right for thumb access
            Button {
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(subtask.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onLongPressGesture {
            viewModel.selectedTaskForDetails = subtask
        }
    }
}

// MARK: - Inline Add Subtask Row

struct FocusInlineAddSubtaskRow: View {
    let parentId: UUID
    @ObservedObject var viewModel: FocusTabViewModel
    @State private var newSubtaskTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Subtask", text: $newSubtaskTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitSubtask()
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
                        Text("Add subtask")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 6)
    }

    private func submitSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        Task {
            await viewModel.createSubtask(title: title, parentId: parentId)
            newSubtaskTitle = ""
            isFocused = true
        }
    }
}

// MARK: - Drag Cancel Bar

private struct DragCancelBar: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(isHighlighted ? .white : .secondary)

            Text("Drop to cancel")
                .font(.subheadline)
                .fontWeight(.medium)
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
                .font(.title3)
                .foregroundColor(info.isCompleted ? .green : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.taskTitle)
                    .font(.body)
                    .strikethrough(info.isCompleted)
                    .foregroundColor(info.isCompleted ? .secondary : .primary)
                    .lineLimit(1)

                if let subtaskText = info.subtaskText {
                    Text(subtaskText)
                        .font(.caption)
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
    FocusTabView()
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
