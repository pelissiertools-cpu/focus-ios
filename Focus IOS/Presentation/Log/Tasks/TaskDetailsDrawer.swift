//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TaskDetailsDrawer<VM: TaskEditingViewModel>: View {
    let task: FocusTask
    let commitment: Commitment?
    let categories: [Category]
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @State private var taskTitle: String
    @State private var commitExpanded = false
    @State private var commitTimeframe: Timeframe = .daily
    @State private var commitSection: Section = .focus
    @State private var commitDates: Set<Date> = []
    @State private var originalCommitDates: Set<Date> = []
    @State private var originalCommitments: [Commitment] = []
    @State private var hasExistingCommitments = false
    @State private var showingRescheduleSheet = false
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var newSubtaskTitle: String = ""
    @State private var showNewSubtaskField = false
    @State private var selectedCategoryId: UUID?
    @State private var selectedPriority: Priority
    @State private var noteText: String
    @State private var showingDeleteConfirmation = false
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false
    @State private var draftSuggestions: [DraftSubtaskEntry] = []
    @State private var pendingDeletions: Set<UUID> = []
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?
    @FocusState private var isNewSubtaskFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSubtask: Bool {
        task.parentTaskId != nil
    }

    private var parentTask: FocusTask? {
        guard let parentId = task.parentTaskId else { return nil }
        return viewModel.findTask(byId: parentId)
    }

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
            .filter { !pendingDeletions.contains($0.id) }
    }

    init(task: FocusTask, viewModel: VM, commitment: Commitment? = nil, categories: [Category] = []) {
        self.task = task
        self.viewModel = viewModel
        self.commitment = commitment
        self.categories = categories
        _taskTitle = State(initialValue: task.title)
        _noteText = State(initialValue: task.description ?? "")
        _selectedCategoryId = State(initialValue: task.categoryId)
        _selectedPriority = State(initialValue: task.priority)
    }

    private var commitPillIsActive: Bool {
        !commitDates.isEmpty || hasExistingCommitments
    }

    private var hasCommitChanges: Bool {
        let currentDates = Set(commitDates.map { Calendar.current.startOfDay(for: $0) })
        return originalCommitDates != currentDates
    }

    private var hasNoteChanges: Bool {
        noteText != (task.description ?? "")
    }

    private var hasChanges: Bool {
        taskTitle != task.title || selectedCategoryId != task.categoryId || selectedPriority != task.priority || !pendingDeletions.isEmpty || !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || !draftSuggestions.isEmpty || hasCommitChanges || hasNoteChanges
    }

    var body: some View {
        DrawerContainer(
            title: isSubtask ? "Subtask Details" : "Task Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                addSubtask()
                commitDraftSuggestions()
                commitPendingDeletions()
                saveCommitChanges()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        // ─── TITLE ───
                        titleCard

                        // ─── SUBTASKS ───
                        if !isSubtask {
                            subtasksCard
                        }

                        // ─── PILL ACTIONS ───
                        actionPillsRow

                        // ─── INLINE COMMIT ───
                        if commitExpanded {
                            inlineCommitCard
                                .id("commitCard")
                        }

                        // ─── CONTEXTUAL ACTIONS ───
                        if contextualActionsVisible {
                            contextualActionsCard
                        }

                        // ─── NOTE ───
                        noteCard
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: commitExpanded) { _, expanded in
                    if expanded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("commitCard", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(.clear)
            .onChange(of: isTitleFocused) { _, isFocused in
                if isFocused && commitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commitExpanded = false
                    }
                }
            }
            .onChange(of: isNewSubtaskFocused) { _, isFocused in
                if isFocused && commitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commitExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId) { _, subtaskId in
                if subtaskId != nil && commitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commitExpanded = false
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .sheet(isPresented: $showingRescheduleSheet) {
                if let commitment = commitment {
                    RescheduleSheet(commitment: commitment, focusViewModel: focusViewModel)
                        .drawerStyle()
                }
            }
            .alert(isSubtask ? "Delete subtask?" : "Delete task?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    _Concurrency.Task { @MainActor in
                        if isSubtask, let parentId = task.parentTaskId {
                            await viewModel.deleteSubtask(task, parentId: parentId)
                        } else if commitment != nil {
                            await focusViewModel.permanentlyDeleteTask(task)
                        } else {
                            await viewModel.deleteTask(task)
                        }
                        dismiss()
                    }
                }
            } message: {
                Text(isSubtask ? "This will permanently delete this subtask." : "This will permanently delete this task and all its commitments.")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Task title", text: $taskTitle, axis: .vertical)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)

            if isSubtask, let parent = parentTask {
                Text(parent.title)
                    .font(.sf(.caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, -8)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
            checkExistingCommitments()
        }
    }

    // MARK: - Subtasks Card

    @ViewBuilder
    private var subtasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Subtasks" label + "Break Down" button
            HStack {
                Text("Subtasks")
                    .font(.sf(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !task.isCompleted {
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
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.5), lineWidth: 1.5)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 14) {
                ForEach(subtasks) { subtask in
                    compactSubtaskRow(subtask)
                }

                // Draft AI suggestions (not yet saved)
                ForEach(draftSuggestions) { draft in
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.sf(.caption2))
                            .foregroundColor(.purple.opacity(0.6))

                        TextField("Subtask", text: draftBinding(for: draft.id))
                            .font(.sf(.body))
                            .textFieldStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                draftSuggestions.removeAll { $0.id == draft.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.sf(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // New subtask entry (shown when focused)
                if showNewSubtaskField || !newSubtaskTitle.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.sf(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Subtask", text: $newSubtaskTitle)
                            .font(.sf(.body))
                            .textFieldStyle(.plain)
                            .focused($isNewSubtaskFocused)
                            .onAppear { isNewSubtaskFocused = true }
                            .onSubmit { addSubtask() }

                        Button {
                            newSubtaskTitle = ""
                            showNewSubtaskField = false
                            isNewSubtaskFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.sf(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // "+ Sub-task" pill button
                if !task.isCompleted {
                    HStack {
                        Button {
                            if !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                addSubtask()
                            }
                            showNewSubtaskField = true
                            isNewSubtaskFocused = true
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
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Compact Subtask Row

    @ViewBuilder
    private func compactSubtaskRow(_ subtask: FocusTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.sf(.caption2))
                .foregroundColor(subtask.isCompleted ? Color.completedPurple.opacity(0.6) : .secondary.opacity(0.5))

            // Editable title
            SubtaskTextField(subtask: subtask, viewModel: viewModel, focusedId: $focusedSubtaskId)

            // Delete X button (staged — committed on save)
            if !subtask.isCompleted {
                Button {
                    pendingDeletions.insert(subtask.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Pills Row

    private var currentCategoryName: String {
        if let id = selectedCategoryId,
           let cat = categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "Category"
    }

    @ViewBuilder
    private var actionPillsRow: some View {
        HStack(spacing: 8) {
            // Priority pill (parent tasks only)
            if !isSubtask {
                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            selectedPriority = priority
                        } label: {
                            if selectedPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(selectedPriority.dotColor)
                            .frame(width: 8, height: 8)
                        Text(LocalizedStringKey(selectedPriority.displayName))
                            .font(.sf(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }

            // Category pill (only in Log view, parent tasks)
            if !isSubtask && commitment == nil {
                Menu {
                    Button {
                        selectedCategoryId = nil
                    } label: {
                        if selectedCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(categories) { category in
                        Button {
                            selectedCategoryId = category.id
                        } label: {
                            if selectedCategoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingNewCategoryAlert = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.sf(.subheadline))
                        Text(LocalizedStringKey(currentCategoryName))
                            .font(.sf(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }

            // Commit pill (only when not committed)
            if commitment == nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commitExpanded.toggle()
                    }
                    if commitExpanded {
                        isTitleFocused = false
                        focusedSubtaskId = nil
                        isNewSubtaskFocused = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .font(.sf(.subheadline))
                        Text("Schedule")
                            .font(.sf(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(commitPillIsActive ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(
                        commitPillIsActive
                            ? .regular.tint(.appRed).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Delete circle
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.sf(.body, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Contextual Actions Card

    private var contextualActionsVisible: Bool {
        commitment != nil
    }

    @ViewBuilder
    private var contextualActionsCard: some View {
        VStack(spacing: 0) {
            // Unschedule from Focus (when scheduled)
            if let commitment = commitment {
                DrawerActionRow(
                    icon: "minus.circle",
                    text: commitment.timeframe.unscheduleLabel
                ) {
                    _Concurrency.Task {
                        await focusViewModel.removeCommitment(commitment)
                        dismiss()
                    }
                }
            }

            // Schedule to lower timeframe (non-daily commitments)
            if let commitment = commitment,
               commitment.canBreakdown,
               let childTimeframe = commitment.childTimeframe {
                DrawerActionRow(icon: "arrow.down.forward.circle", text: "Schedule to \(childTimeframe.displayName)") {
                    focusViewModel.selectedCommitmentForCommit = commitment
                    focusViewModel.showCommitSheet = true
                    dismiss()
                }
            }

            // Schedule Subtask to lower timeframe
            if isSubtask && commitment == nil {
                if let parentId = task.parentTaskId,
                   let parentCommitment = focusViewModel.commitments.first(where: {
                       $0.taskId == parentId &&
                       focusViewModel.isSameTimeframe($0.commitmentDate, timeframe: focusViewModel.selectedTimeframe, selectedDate: focusViewModel.selectedDate)
                   }),
                   parentCommitment.timeframe != .daily {
                    DrawerActionRow(icon: "arrow.down.forward.circle", text: "Schedule to \(parentCommitment.childTimeframe?.displayName ?? "...")") {
                        focusViewModel.selectedSubtaskForCommit = task
                        focusViewModel.selectedParentCommitmentForSubtaskCommit = parentCommitment
                        focusViewModel.showSubtaskCommitSheet = true
                        dismiss()
                    }
                }
            }

            // Reschedule (committed, non-completed parent task)
            if commitment != nil, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "calendar", text: "Reschedule") {
                    showingRescheduleSheet = true
                }
            }

            // Unschedule (remove from timeline, keep commitment)
            if let commitment = commitment, commitment.scheduledTime != nil {
                DrawerActionRow(icon: "calendar.badge.minus", text: "Unschedule") {
                    _Concurrency.Task { @MainActor in
                        await focusViewModel.timelineVM.unscheduleCommitment(commitment.id)
                        dismiss()
                    }
                }
            }

            // Push to Next (committed, non-completed parent task)
            if let commitment = commitment, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "arrow.turn.right.down", text: "Push to \(commitment.timeframe.nextTimeframeLabel)") {
                    _Concurrency.Task {
                        let success = await focusViewModel.pushCommitmentToNext(commitment)
                        if success { dismiss() }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.sf(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.sf(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $noteText)
                    .font(.sf(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Inline Commit Card

    @ViewBuilder
    private var inlineCommitCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section picker (Focus/Extra)
            Picker("Section", selection: $commitSection) {
                Text("Focus").tag(Section.focus)
                Text("Extra").tag(Section.extra)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            // Calendar picker
            ScrollView {
                UnifiedCalendarPicker(
                    selectedDates: $commitDates,
                    selectedTimeframe: $commitTimeframe
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 350)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .onAppear {
            fetchTaskCommitments()
        }
        .onChange(of: commitTimeframe) {
            fetchTaskCommitments()
        }
        .onChange(of: commitSection) {
            fetchTaskCommitments()
        }
    }

    // MARK: - Commit Data

    private func checkExistingCommitments() {
        _Concurrency.Task {
            do {
                let commitments = try await CommitmentRepository().fetchCommitments(forTask: task.id)
                await MainActor.run {
                    hasExistingCommitments = !commitments.isEmpty
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func fetchTaskCommitments() {
        _Concurrency.Task {
            do {
                let commitmentRepository = CommitmentRepository()
                let commitments = try await commitmentRepository.fetchCommitments(forTask: task.id)

                let filtered = commitments.filter {
                    $0.timeframe == commitTimeframe && $0.section == commitSection
                }

                await MainActor.run {
                    originalCommitments = filtered
                    originalCommitDates = Set(filtered.map { Calendar.current.startOfDay(for: $0.commitmentDate) })
                    commitDates = Set(filtered.map { $0.commitmentDate })
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func saveCommitChanges() {
        let currentDates = Set(commitDates.map { Calendar.current.startOfDay(for: $0) })
        guard originalCommitDates != currentDates else { return }

        let capturedOriginalCommitments = originalCommitments
        let capturedSection = commitSection
        let capturedTimeframe = commitTimeframe

        _Concurrency.Task {
            do {
                let commitmentRepository = CommitmentRepository()
                let allCommitments = try await commitmentRepository.fetchCommitments(forTask: task.id)
                let otherSection: Section = capturedSection == .focus ? .extra : .focus

                let datesToAdd = currentDates.subtracting(originalCommitDates)
                let datesToRemove = originalCommitDates.subtracting(currentDates)

                for date in datesToRemove {
                    if let commitment = capturedOriginalCommitments.first(where: {
                        Calendar.current.startOfDay(for: $0.commitmentDate) == date
                    }) {
                        try await commitmentRepository.deleteCommitment(id: commitment.id)
                    }
                }

                for date in datesToAdd {
                    if let conflicting = allCommitments.first(where: {
                        $0.section == otherSection &&
                        $0.timeframe == capturedTimeframe &&
                        Calendar.current.startOfDay(for: $0.commitmentDate) == Calendar.current.startOfDay(for: date)
                    }) {
                        try await commitmentRepository.deleteCommitment(id: conflicting.id)
                    }

                    let newCommitment = Commitment(
                        userId: task.userId,
                        taskId: task.id,
                        timeframe: capturedTimeframe,
                        section: capturedSection,
                        commitmentDate: date,
                        sortOrder: 0
                    )
                    _ = try await commitmentRepository.createCommitment(newCommitment)
                }

                await focusViewModel.fetchCommitments()
            } catch {
                // Silently fail
            }
        }
    }

    // MARK: - Actions

    private func saveTitle() {
        guard taskTitle != task.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(task, newTitle: taskTitle)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(task, newNote: note.isEmpty ? nil : note)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != task.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(task, categoryId: selectedCategoryId)
        }
    }

    private func savePriority() {
        guard selectedPriority != task.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(task, priority: selectedPriority)
        }
    }

    private func commitPendingDeletions() {
        let allSubtasks = viewModel.getSubtasks(for: task.id)
        for subtaskId in pendingDeletions {
            if let subtask = allSubtasks.first(where: { $0.id == subtaskId }) {
                _Concurrency.Task {
                    await viewModel.deleteSubtask(subtask, parentId: task.id)
                }
            }
        }
    }

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newSubtaskTitle
        newSubtaskTitle = ""
        isNewSubtaskFocused = true
        _Concurrency.Task {
            if let commitment = commitment {
                await focusViewModel.createSubtask(title: title, parentId: task.id, parentCommitment: commitment)
            } else {
                await viewModel.createSubtask(title: title, parentId: task.id)
            }
        }
    }

    private func generateBreakdown() {
        isGeneratingBreakdown = true
        let existingTitles = subtasks.map { $0.title } + draftSuggestions.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: task.title,
                    description: task.description,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Keep manually-added drafts, replace AI-generated ones
                    let manualDrafts = draftSuggestions.filter { !$0.isAISuggested }
                    draftSuggestions = manualDrafts + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail — user can retry or add manually
            }
            isGeneratingBreakdown = false
        }
    }

    private func commitDraftSuggestions() {
        for draft in draftSuggestions {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            _Concurrency.Task {
                if let commitment = commitment {
                    await focusViewModel.createSubtask(title: title, parentId: task.id, parentCommitment: commitment)
                } else {
                    await viewModel.createSubtask(title: title, parentId: task.id)
                }
            }
        }
    }

    private func draftBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSuggestions.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = draftSuggestions.firstIndex(where: { $0.id == id }) {
                    draftSuggestions[idx].title = newValue
                }
            }
        )
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: task)
            dismiss()
        }
    }
}

// MARK: - Inline Subtask TextField

private struct SubtaskTextField<VM: TaskEditingViewModel>: View {
    let subtask: FocusTask
    @ObservedObject var viewModel: VM
    var focusedId: FocusState<UUID?>.Binding
    @State private var editingTitle: String

    init(subtask: FocusTask, viewModel: VM, focusedId: FocusState<UUID?>.Binding) {
        self.subtask = subtask
        self.viewModel = viewModel
        self.focusedId = focusedId
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        TextField("Subtask", text: $editingTitle)
            .font(.sf(.body))
            .textFieldStyle(.plain)
            .strikethrough(subtask.isCompleted)
            .foregroundColor(subtask.isCompleted ? .secondary : .primary)
            .focused(focusedId, equals: subtask.id)
            .onSubmit { saveTitle() }
            .onChange(of: focusedId.wrappedValue) { _, newValue in
                if newValue != subtask.id {
                    saveTitle()
                }
            }
    }

    private func saveTitle() {
        guard editingTitle != subtask.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(subtask, newTitle: editingTitle)
        }
    }
}
