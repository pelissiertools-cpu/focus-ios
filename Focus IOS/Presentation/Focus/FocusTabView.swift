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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date Navigator with view mode toggle on the left
                DateNavigator(
                    selectedDate: $viewModel.selectedDate,
                    timeframe: viewMode == .focus ? viewModel.selectedTimeframe : .daily,
                    compact: viewMode == .schedule,
                    onTap: { showCalendarPicker = true }
                ) {
                    // View mode toggle icons
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = .focus
                            }
                        } label: {
                            Image(systemName: "target")
                                .font(.title3)
                                .foregroundColor(viewMode == .focus ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = .schedule
                            }
                        } label: {
                            Image(systemName: "calendar")
                                .font(.title3)
                                .foregroundColor(viewMode == .schedule ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onChange(of: viewModel.selectedDate) {
                    _Concurrency.Task { @MainActor in
                        await viewModel.fetchCommitments()
                    }
                }

                if viewMode == .focus {
                    // MARK: - Focus Mode Content

                    // Timeframe Picker
                    Picker("Timeframe", selection: $viewModel.selectedTimeframe) {
                        Text("Daily").tag(Timeframe.daily)
                        Text("Weekly").tag(Timeframe.weekly)
                        Text("Monthly").tag(Timeframe.monthly)
                        Text("Yearly").tag(Timeframe.yearly)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .onChange(of: viewModel.selectedTimeframe) {
                        _Concurrency.Task { @MainActor in
                            await viewModel.fetchCommitments()
                        }
                    }

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
                    CalendarTimelineView(viewModel: viewModel)
                }
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
                    viewModel.addTaskSection = section
                    viewModel.showAddTaskSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(section == .focus && !viewModel.canAddTask(to: .focus))
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
                if sectionCommitments.isEmpty {
                    Text("No to-dos yet. Tap + to add one.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
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
                                        onDragEnded: { onDragEnded?() }
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
                                .background(Color(.secondarySystemBackground))
                                .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                                .scaleEffect(isDragging ? 1.03 : 1.0)
                                .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                                .zIndex(isDragging ? 1 : 0)
                                .transaction { t in
                                    if isDragging { t.animation = nil }
                                }
                            }
                        }

                        // Completed commitments — inline below for Focus, Done pill for Extra
                        if section == .focus && !completedCommitments.isEmpty {
                            ForEach(Array(completedCommitments.enumerated()), id: \.element.id) { index, commitment in
                                if let task = viewModel.tasksMap[commitment.taskId] {
                                    Divider()
                                    CommitmentRow(commitment: commitment, task: task, section: section, viewModel: viewModel)
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
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

                                TextField("Subtask title", text: $draftSubtasks[index].title)
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

        _Concurrency.Task { @MainActor in
            guard let result = await viewModel.createTaskWithCommitment(title: title, section: section) else {
                return
            }

            for subtaskTitle in subtasksToCreate {
                await viewModel.createSubtask(title: subtaskTitle, parentId: result.taskId, parentCommitment: result.commitment)
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
                            .font(section == .focus ? .title3 : .body)
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                        if task.type == .list {
                            Image(systemName: "list.bullet")
                                .font(section == .focus ? .subheadline : .caption)
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
            .padding(.vertical, section == .focus ? 14 : 8)

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
                TextField("Subtask title", text: $newSubtaskTitle)
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
                        Text("Add")
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
            // Keep editing mode open for adding more subtasks
        }
    }
}

#Preview {
    let authService = AuthService()
    FocusTabView()
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
