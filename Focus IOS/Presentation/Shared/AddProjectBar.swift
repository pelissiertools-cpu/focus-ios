//
//  AddProjectBar.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct AddProjectBar: View {
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    var onSaved: (() -> Void)?
    var onDismiss: () -> Void

    // State
    @State private var title = ""
    @State private var draftTasks: [DraftTask] = []
    @State private var categoryId: UUID?
    @State private var priority: Priority = .low
    @State private var scheduleDates: Set<Date> = []
    @State private var scheduleDatesSnapshot: Set<Date> = []
    @State private var timeframe: Timeframe = .daily
    @State private var section: Section = .todo
    @State private var scheduleExpanded = false
    @State private var optionsExpanded = false

    @FocusState private var titleFocused: Bool
    @FocusState private var focusedTaskId: UUID?

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var categoryPillLabel: String {
        if let categoryId,
           let category = projectsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Create a new project", text: $title)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .submitLabel(.return)
                .onSubmit { save() }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Tasks + subtasks area
            if !draftTasks.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draftTasks) { task in
                        projectTaskDraftRow(task: task)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            // Schedule expansion
            if scheduleExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Section", selection: $section) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $scheduleDates,
                        selectedTimeframe: $timeframe
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleDates.removeAll()
                            scheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .accessibilityLabel("Clear schedule")
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = scheduleDates != scheduleDatesSnapshot
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Confirm schedule")
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            // Row 1: [Task] [...] Spacer [Checkmark]
            if !scheduleExpanded {
                HStack(spacing: 8) {
                    Button {
                        addNewTask()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.inter(.caption))
                            Text("Task")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            optionsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.caption, weight: .bold))
                            .foregroundColor(.black)
                            .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .accessibilityLabel("More options")
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(isTitleEmpty ? .secondary : .white)
                            .frame(width: 36, height: 36)
                            .background(
                                isTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Save project")
                    .buttonStyle(.plain)
                    .disabled(isTitleEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if optionsExpanded && !scheduleExpanded {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            categoryId = nil
                        } label: {
                            if categoryId == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }
                        ForEach(projectsViewModel.categories) { category in
                            Button {
                                categoryId = category.id
                            } label: {
                                if self.categoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.inter(.caption))
                            Text(LocalizedStringKey(categoryPillLabel))
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                    }

                    Button {
                        scheduleDatesSnapshot = scheduleDates
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.inter(.caption))
                            Text("Schedule")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(!scheduleDates.isEmpty ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(!scheduleDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Button {
                                priority = p
                            } label: {
                                if priority == p {
                                    Label(p.displayName, systemImage: "checkmark")
                                } else {
                                    Text(p.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(priority.dotColor)
                                .frame(width: 8, height: 8)
                            Text(priority.displayName)
                                .font(.inter(.caption))
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
        }
    }

    // MARK: - Draft Task Row

    @ViewBuilder
    private func projectTaskDraftRow(task: DraftTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.inter(.caption2))
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: taskBinding(for: task.id), axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($focusedTaskId, equals: task.id)
                .lineLimit(1...3)
                .onChange(of: taskBinding(for: task.id).wrappedValue) { _, newValue in
                    if newValue.contains("\n") {
                        if let idx = draftTasks.firstIndex(where: { $0.id == task.id }) {
                            draftTasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                        }
                        addNewSubtask(toTask: task.id)
                    }
                }

            Button {
                removeTask(id: task.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Remove task")
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Sub-task", text: subtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.inter(.body))
                    .textFieldStyle(.plain)
                    .focused($focusedTaskId, equals: subtask.id)
                    .lineLimit(1...3)
                    .onChange(of: subtaskBinding(forSubtask: subtask.id, inTask: task.id).wrappedValue) { _, newValue in
                        if newValue.contains("\n") {
                            if let tIdx = draftTasks.firstIndex(where: { $0.id == task.id }),
                               let sIdx = draftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtask.id }) {
                                draftTasks[tIdx].subtasks[sIdx].title = newValue.replacingOccurrences(of: "\n", with: "")
                            }
                            addNewSubtask(toTask: task.id)
                        }
                    }

                Button {
                    removeSubtask(id: subtask.id, fromTask: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Remove subtask")
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .padding(.top, 12)

        // "+ Sub-task" button
        Button {
            addNewSubtask(toTask: task.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.inter(.subheadline))
                Text("Sub-task")
                    .font(.inter(.subheadline))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Helpers

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let tasks = draftTasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        let catId = categoryId
        let pri = priority
        let scheduleEnabled = !scheduleDates.isEmpty
        let tf = timeframe
        let sec = section
        let dates = scheduleDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        titleFocused = true
        focusedTaskId = nil

        title = ""
        draftTasks = []
        scheduleDates = []
        scheduleExpanded = false
        optionsExpanded = false
        priority = .low

        _Concurrency.Task { @MainActor in
            guard let projectId = await projectsViewModel.saveNewProject(
                title: trimmedTitle,
                categoryId: catId,
                priority: pri,
                draftTasks: tasks
            ) else { return }

            if scheduleEnabled && !dates.isEmpty {
                guard let userId = projectsViewModel.authService.currentUser?.id else { return }
                for date in dates {
                    let schedule = Schedule(
                        userId: userId,
                        taskId: projectId,
                        timeframe: tf,
                        section: sec,
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

            onSaved?()
        }
    }

    private func addNewTask() {
        let newTask = DraftTask()
        withAnimation(.easeInOut(duration: 0.15)) {
            draftTasks.append(newTask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedTaskId = newTask.id
        }
    }

    private func addNewSubtask(toTask taskId: UUID) {
        guard let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let newSubtask = DraftSubtask(title: "")
        withAnimation(.easeInOut(duration: 0.15)) {
            draftTasks[tIdx].subtasks.append(newSubtask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedTaskId = newSubtask.id
        }
    }

    private func removeTask(id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            draftTasks.removeAll { $0.id == id }
        }
    }

    private func removeSubtask(id: UUID, fromTask taskId: UUID) {
        guard let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            draftTasks[tIdx].subtasks.removeAll { $0.id == id }
        }
    }

    private func taskBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: { draftTasks.first(where: { $0.id == taskId })?.title ?? "" },
            set: { newValue in
                if let idx = draftTasks.firstIndex(where: { $0.id == taskId }) {
                    draftTasks[idx].title = newValue
                }
            }
        )
    }

    private func subtaskBinding(forSubtask subtaskId: UUID, inTask taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }),
                      let s = draftTasks[tIdx].subtasks.first(where: { $0.id == subtaskId })
                else { return "" }
                return s.title
            },
            set: { newValue in
                if let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }),
                   let sIdx = draftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) {
                    draftTasks[tIdx].subtasks[sIdx].title = newValue
                }
            }
        )
    }
}
