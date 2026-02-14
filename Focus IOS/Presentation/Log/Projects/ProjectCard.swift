//
//  ProjectCard.swift
//  Focus IOS
//

import SwiftUI
import Auth

// MARK: - Project Card

struct ProjectCard: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    private var taskProgress: (completed: Int, total: Int) {
        viewModel.taskProgress(for: project.id)
    }

    private var subtaskProgress: (completed: Int, total: Int) {
        viewModel.subtaskProgress(for: project.id)
    }

    private var progressPercentage: Double {
        viewModel.progressPercentage(for: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            projectHeader

            // Progress bar
            if !project.isCompleted && taskProgress.total > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 3)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progressPercentage, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal)
                .padding(.bottom, viewModel.isExpanded(project.id) ? 0 : 12)
            }

            // Expanded content
            if viewModel.isExpanded(project.id) {
                expandedContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    // MARK: - Header

    private var projectHeader: some View {
        HStack(spacing: 12) {
            // Project icon
            Image(systemName: "archivebox.fill")
                .font(.title3)
                .foregroundColor(project.isCompleted ? .secondary : .orange)

            // Title and progress
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)
                    .strikethrough(project.isCompleted)
                    .foregroundColor(project.isCompleted ? .secondary : .primary)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Task")
                            .font(.caption)
                        Text("\(taskProgress.completed)/\(taskProgress.total)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text("Sub Task")
                            .font(.caption)
                        Text("\(subtaskProgress.completed)/\(subtaskProgress.total)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if project.isCompleted {
                // Blue checkmark for completed projects
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            } else if !viewModel.isEditMode, let onDragChanged, let onDragEnded {
                // Drag handle
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("projectList"))
                            .onChanged { value in onDragChanged(value) }
                            .onEnded { _ in onDragEnded() }
                    )
            } else {
                DragHandleView()
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            _Concurrency.Task { @MainActor in
                await viewModel.toggleExpanded(project.id)
            }
        }
        .onLongPressGesture {
            viewModel.selectedProjectForDetails = project
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal)

            if viewModel.isLoadingProjectTasks.contains(project.id) {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding()
            } else {
                let tasks = viewModel.projectTasksMap[project.id] ?? []

                if tasks.isEmpty {
                    Text("No tasks yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(tasks) { task in
                        VStack(spacing: 0) {
                            ProjectTaskRow(
                                task: task,
                                projectId: project.id,
                                viewModel: viewModel
                            )

                            // Subtasks (nested directly under parent)
                            if viewModel.isTaskExpanded(task.id) {
                                ProjectSubtasksList(
                                    parentTask: task,
                                    viewModel: viewModel
                                )
                                InlineAddSubtaskForProjectRow(
                                    parentId: task.id,
                                    viewModel: viewModel
                                )
                            }
                        }
                    }
                }

                // Add task row
                InlineAddProjectTaskRow(
                    projectId: project.id,
                    viewModel: viewModel
                )
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Project Task Row

struct ProjectTaskRow: View {
    let task: FocusTask
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel

    private var subtaskCount: (completed: Int, total: Int) {
        let subtasks = viewModel.subtasksMap[task.id] ?? []
        let completed = subtasks.filter { $0.isCompleted }.count
        return (completed, subtasks.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Expand indicator
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary)

            // Task title + subtask count
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
            }

            Spacer()

            // Subtask count badge
            if subtaskCount.total > 0 {
                Text("\(subtaskCount.completed)/\(subtaskCount.total)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }

            // Completion button
            Button {
                _Concurrency.Task {
                    await viewModel.toggleTaskCompletion(task, projectId: projectId)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? .blue : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            _Concurrency.Task {
                await viewModel.toggleTaskExpanded(task.id)
            }
        }
        .onLongPressGesture {
            viewModel.selectedTaskForDetails = task
        }
    }
}

// MARK: - Project Subtasks List

struct ProjectSubtasksList: View {
    let parentTask: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingSubtasks.contains(parentTask.id) {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                // Uncompleted subtasks
                ForEach(viewModel.getUncompletedSubtasks(for: parentTask.id)) { subtask in
                    ProjectSubtaskRow(
                        subtask: subtask,
                        parentId: parentTask.id,
                        viewModel: viewModel
                    )
                }

                // Completed subtasks
                ForEach(viewModel.getCompletedSubtasks(for: parentTask.id)) { subtask in
                    ProjectSubtaskRow(
                        subtask: subtask,
                        parentId: parentTask.id,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(.leading, 32)
    }
}

// MARK: - Project Subtask Row

struct ProjectSubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.subheadline)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            Button {
                _Concurrency.Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(subtask.isCompleted ? .blue : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onLongPressGesture {
            viewModel.selectedTaskForDetails = subtask
        }
    }
}

// MARK: - Inline Add Project Task Row

struct InlineAddProjectTaskRow: View {
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var newTaskTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Task title", text: $newTaskTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitTask()
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
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func submitTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        _Concurrency.Task {
            await viewModel.createProjectTask(title: title, projectId: projectId)
            newTaskTitle = ""
        }
    }
}

// MARK: - Inline Add Subtask For Project Row

struct InlineAddSubtaskForProjectRow: View {
    let parentId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var newTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Subtask title", text: $newTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitSubtask()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.caption)
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
        .padding(.horizontal)
        .padding(.leading, 32)
    }

    private func submitSubtask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        _Concurrency.Task {
            await viewModel.createSubtask(title: title, parentId: parentId)
            newTitle = ""
        }
    }
}

// MARK: - Add Project Sheet

struct AddProjectSheet: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var authService: AuthService
    @State private var projectTitle = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var draftTasks: [DraftTask] = []
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var commitAfterCreate = false
    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .focus
    @State private var selectedDates: Set<Date> = []
    @State private var hasScheduledTime = false
    @State private var scheduledTime: Date = {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundUp = ((minute / 15) + 1) * 15
        return calendar.date(byAdding: .minute, value: roundUp - minute, to: now) ?? now
    }()
    @State private var sheetDetent: PresentationDetent = .fraction(0.75)
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Project name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        TextField("Project name", text: $projectTitle)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }

                    // Category picker — always visible
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        HStack {
                            Picker("Category", selection: $selectedCategoryId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(viewModel.categories) { category in
                                    Text(category.name).tag(category.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button {
                                showNewCategory = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("New")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if showNewCategory {
                            HStack {
                                TextField("Category name", text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)

                                Button("Add") {
                                    submitNewCategory()
                                }
                                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // Tasks section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tasks")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        ForEach($draftTasks) { $draftTask in
                            DraftTaskCard(
                                draftTask: $draftTask,
                                onDelete: {
                                    draftTasks.removeAll { $0.id == draftTask.id }
                                }
                            )
                        }

                        // Add task button
                        Button {
                            draftTasks.append(DraftTask())
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                Text("Add Task")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    // Commit & schedule toggles
                    CommitScheduleSection(
                        commitAfterCreate: $commitAfterCreate,
                        selectedTimeframe: $selectedTimeframe,
                        selectedSection: $selectedSection,
                        selectedDates: $selectedDates,
                        hasScheduledTime: $hasScheduledTime,
                        scheduledTime: $scheduledTime
                    )

                    // Create button
                    Button {
                        createProject()
                    } label: {
                        Text("Create Project")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(projectTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.blue.opacity(0.5)
                                          : Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(projectTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                    .id("createProjectButton")
                }
                .padding()
            }
            .onChange(of: commitAfterCreate) { _, isOn in
                if isOn {
                    titleFocused = false
                }
                withAnimation {
                    sheetDetent = isOn ? .large : .fraction(0.75)
                }
                if isOn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("createProjectButton", anchor: .bottom)
                        }
                    }
                }
            }
            } // ScrollViewReader
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showingAddProject = false
                    }
                }
            }
            .onAppear {
                titleFocused = true
            }
            .presentationDetents([.fraction(0.75), .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    private func createProject() {
        _Concurrency.Task { @MainActor in
            guard let projectId = await viewModel.saveNewProject(
                title: projectTitle,
                categoryId: selectedCategoryId,
                draftTasks: draftTasks
            ) else { return }

            // Create commitments if commit toggle is on and dates selected
            if commitAfterCreate && !selectedDates.isEmpty {
                guard let userId = authService.currentUser?.id else { return }
                let commitmentRepository = CommitmentRepository()
                for date in selectedDates {
                    let commitment = Commitment(
                        userId: userId,
                        taskId: projectId,
                        timeframe: selectedTimeframe,
                        section: selectedSection,
                        commitmentDate: date,
                        sortOrder: 0,
                        scheduledTime: hasScheduledTime ? scheduledTime : nil,
                        durationMinutes: hasScheduledTime ? 30 : nil
                    )
                    _ = try? await commitmentRepository.createCommitment(commitment)
                }
                await focusViewModel.fetchCommitments()
                await viewModel.fetchCommittedTaskIds()
            }

            viewModel.showingAddProject = false
        }
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.createCategory(name: name)
            if let created = viewModel.categories.last {
                selectedCategoryId = created.id
            }
            newCategoryName = ""
            showNewCategory = false
        }
    }
}

// MARK: - Draft Task Card (for AddProjectSheet)

struct DraftTaskCard: View {
    @Binding var draftTask: DraftTask
    let onDelete: () -> Void
    @FocusState private var taskTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task title row
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Task title", text: $draftTask.title)
                    .font(.subheadline)
                    .focused($taskTitleFocused)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Subtasks (nested under their parent)
            ForEach(Array(draftTask.subtasks.enumerated()), id: \.element.id) { index, _ in
                HStack(spacing: 8) {
                    TextField("Subtask title", text: $draftTask.subtasks[index].title)
                        .font(.caption)

                    Button {
                        draftTask.subtasks.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 28)
            }

            // Add subtask button
            Button {
                draftTask.subtasks.append(DraftSubtask(title: ""))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption)
                    Text("Add subtask")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        }
    }
}

// MARK: - Project Details Drawer

struct ProjectDetailsDrawer: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var projectTitle: String
    @Environment(\.dismiss) private var dismiss

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
    }

    var body: some View {
        NavigationView {
            List {
                SwiftUI.Section("Title") {
                    TextField("Project title", text: $projectTitle)
                }

                SwiftUI.Section("Statistics") {
                    let taskProg = viewModel.taskProgress(for: project.id)
                    let subtaskProg = viewModel.subtaskProgress(for: project.id)

                    Label("\(taskProg.completed)/\(taskProg.total) tasks completed", systemImage: "checklist")
                        .foregroundColor(.secondary)

                    Label("\(subtaskProg.completed)/\(subtaskProg.total) subtasks completed", systemImage: "list.bullet.indent")
                        .foregroundColor(.secondary)
                }

                SwiftUI.Section {
                    Button(role: .destructive) {
                        _Concurrency.Task {
                            await viewModel.deleteProject(project)
                            dismiss()
                        }
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Project Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
