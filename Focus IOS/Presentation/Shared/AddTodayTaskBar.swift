//
//  AddTodayTaskBar.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct AddTodayTaskBar: View {
    @ObservedObject var taskListVM: TaskListViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    let authService: AuthService
    var onSaved: (() -> Void)?

    // State
    @State private var title = ""
    @State private var subtasks: [DraftSubtaskEntry] = []
    @State private var categoryId: UUID?
    @State private var priority: Priority = .low
    @State private var optionsExpanded = false
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false

    @FocusState private var titleFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var categoryPillLabel: String {
        if let categoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add task for today", text: $title)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .submitLabel(.return)
                .onSubmit { save() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            // Subtasks
            DraftSubtaskListEditor(
                subtasks: $subtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            // Row 1: [Sub-task] [...] Spacer [AI] [Checkmark]
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        optionsExpanded.toggle()
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
                .accessibilityLabel("More options")
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
                                .foregroundColor(!isTitleEmpty ? .blue : .primary)
                        }
                        Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                            .font(.inter(.caption, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(
                        !isTitleEmpty ? Color.pillBackground : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTitleEmpty || isGeneratingBreakdown)

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isTitleEmpty ? .secondary : .white)
                        .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                        .background(
                            isTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                            in: Circle()
                        )
                }
                .accessibilityLabel("Save task")
                .buttonStyle(.plain)
                .disabled(isTitleEmpty)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.bottom, AppStyle.Spacing.tiny)

            // Row 2: [Category] [Priority]
            if optionsExpanded {
                HStack(spacing: AppStyle.Spacing.compact) {
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
                        ForEach(taskListVM.categories) { category in
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
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "folder")
                                .font(.inter(.caption))
                            Text(LocalizedStringKey(categoryPillLabel))
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                    }

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
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Circle()
                                .fill(priority.dotColor)
                                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                            Text(priority.displayName)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
        }
    }

    // MARK: - Helpers

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let subtaskTitles = subtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let catId = categoryId
        let pri = priority

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        titleFocused = true
        focusedSubtaskId = nil

        title = ""
        subtasks = []
        optionsExpanded = false
        priority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            guard let userId = authService.currentUser?.id else { return }
            let taskRepo = TaskRepository()
            let scheduleRepo = ScheduleRepository()

            do {
                let newTask = FocusTask(
                    userId: userId,
                    title: trimmedTitle,
                    type: .task,
                    isCompleted: false,
                    isInLibrary: true,
                    priority: pri,
                    categoryId: catId
                )
                let created = try await taskRepo.createTask(newTask)

                // Create subtasks
                for subtaskTitle in subtaskTitles {
                    _ = try await taskRepo.createSubtask(
                        title: subtaskTitle,
                        parentTaskId: created.id,
                        userId: userId
                    )
                }

                // Auto-schedule for today in todo section
                let today = Calendar.current.startOfDay(for: Date())
                let schedule = Schedule(
                    userId: userId,
                    taskId: created.id,
                    timeframe: .daily,
                    section: .todo,
                    scheduleDate: today,
                    sortOrder: 0
                )
                _ = try await scheduleRepo.createSchedule(schedule)

                await focusViewModel.fetchSchedules()
                await taskListVM.fetchTasks()
            } catch {
                // silently fail
            }

            onSaved?()
        }
    }

    private func addNewSubtask() {
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            subtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func generateBreakdown() {
        let taskTitle = title.trimmingCharacters(in: .whitespaces)
        guard !taskTitle.isEmpty else { return }
        isGeneratingBreakdown = true
        _Concurrency.Task { @MainActor in
            do {
                let aiService = AIService()
                let suggestions = try await aiService.generateSubtasks(title: taskTitle, description: nil)
                withAnimation(.easeInOut(duration: 0.2)) {
                    subtasks.append(contentsOf: suggestions.map { DraftSubtaskEntry(title: $0) })
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail
            }
            isGeneratingBreakdown = false
        }
    }
}
