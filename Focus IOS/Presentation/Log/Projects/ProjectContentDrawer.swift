//
//  ProjectContentDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ProjectContentView: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var projectTitle: String
    @State private var editingSectionId: UUID?
    @FocusState private var isTitleFocused: Bool

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Project title — editable inline
                TextField("Project name", text: $projectTitle, axis: .vertical)
                    .font(.inter(.title2, weight: .bold))
                    .foregroundColor(.primary)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onSubmit { saveProjectTitle() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Task/section list
                contentList
            }
            .padding(.bottom, 120)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    saveProjectTitle()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        _Concurrency.Task {
                            await viewModel.createSection(
                                title: "",
                                projectId: project.id
                            )
                            // Focus the newly created section
                            if let tasks = viewModel.projectTasksMap[project.id],
                               let newSection = tasks.last(where: { $0.isSection }) {
                                editingSectionId = newSection.id
                            }
                        }
                    } label: {
                        Label("Add section", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .background(Color.pillBackground, in: Circle())
                }
            }
        }
        .task {
            if viewModel.projectTasksMap[project.id] == nil {
                await viewModel.fetchProjectTasks(for: project.id)
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused { saveProjectTitle() }
        }
    }

    private func saveProjectTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(project, newTitle: trimmed)
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        if viewModel.isLoadingProjectTasks.contains(project.id) {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .padding()
        } else {
            let items = viewModel.flattenedProjectItems(for: project.id)

            if items.count <= 1 {
                // Only addTaskRow — no tasks yet
                Text("No tasks yet")
                    .font(.inter(.headline))
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                InlineAddRow(
                    placeholder: "Task title",
                    buttonLabel: "Add task",
                    onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                    isAnyAddFieldActive: $isInlineAddFocused,
                    verticalPadding: 8
                )
                .padding(.horizontal, 20)
            } else {
                List {
                    ForEach(items) { item in
                        switch item {
                        case .section(let section):
                            ProjectSectionRow(
                                section: section,
                                viewModel: viewModel,
                                projectId: project.id,
                                editingSectionId: $editingSectionId
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .task(let task):
                            Group {
                                if task.parentTaskId != nil {
                                    ProjectSubtaskRow(
                                        subtask: task,
                                        parentId: task.parentTaskId!,
                                        viewModel: viewModel
                                    )
                                    .padding(.leading, 32)
                                } else {
                                    ProjectTaskRow(
                                        task: task,
                                        projectId: project.id,
                                        viewModel: viewModel
                                    )
                                }
                            }
                            .moveDisabled(task.isCompleted)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.visible)

                        case .addSubtaskRow(let parentId):
                            InlineAddRow(
                                placeholder: "Subtask title",
                                buttonLabel: "Add subtask",
                                onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                                isAnyAddFieldActive: $isInlineAddFocused,
                                iconFont: .inter(.caption),
                                verticalPadding: 6
                            )
                            .padding(.leading, 32)
                            .moveDisabled(true)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .addTaskRow:
                            InlineAddRow(
                                placeholder: "Task title",
                                buttonLabel: "Add task",
                                onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                                isAnyAddFieldActive: $isInlineAddFocused,
                                verticalPadding: 8
                            )
                            .moveDisabled(true)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.handleProjectContentFlatMove(from: from, to: to, projectId: project.id)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .keyboardDismissOverlay(isActive: $isInlineAddFocused)
                .frame(minHeight: items.reduce(CGFloat(0)) { sum, item in
                    switch item {
                    case .section: return sum + 52
                    case .task(let t) where t.parentTaskId == nil: return sum + 52
                    case .addTaskRow: return sum + 52
                    case .addSubtaskRow: return sum + 40
                    default: return sum + 40
                    }
                })
            }
        }
    }
}

// MARK: - Project Section Row

struct ProjectSectionRow: View {
    let section: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    let projectId: UUID
    @Binding var editingSectionId: UUID?
    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(section: FocusTask, viewModel: ProjectsViewModel, projectId: UUID, editingSectionId: Binding<UUID?>) {
        self.section = section
        self.viewModel = viewModel
        self.projectId = projectId
        self._editingSectionId = editingSectionId
        _sectionTitle = State(initialValue: section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Section name", text: $sectionTitle)
                .font(.inter(.headline, weight: .bold))
                .foregroundColor(.appRed)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit { saveSectionTitle() }
                .padding(.top, 16)

            Rectangle()
                .fill(Color.appRed.opacity(0.4))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isEditing = true
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Section?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteSection(section, projectId: projectId)
                }
            }
        } message: {
            Text("This will remove the section header. Tasks will not be deleted.")
        }
        .onChange(of: editingSectionId) { _, newId in
            if newId == section.id {
                isEditing = true
                editingSectionId = nil
            }
        }
        .onChange(of: isEditing) { _, focused in
            if !focused { saveSectionTitle() }
        }
    }

    private func saveSectionTitle() {
        let trimmed = sectionTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Delete empty sections
            _Concurrency.Task {
                await viewModel.deleteSection(section, projectId: projectId)
            }
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await viewModel.renameSection(section, newTitle: trimmed)
        }
    }
}
