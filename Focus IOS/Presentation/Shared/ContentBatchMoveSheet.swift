//
//  ContentBatchMoveSheet.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Source type enum

enum ContentBatchMoveSource {
    case project(id: UUID, viewModel: ProjectsViewModel)
    case list(id: UUID, viewModel: ListsViewModel)
}

struct ContentBatchMoveSheet: View {
    let source: ContentBatchMoveSource
    @Environment(\.dismiss) private var dismiss
    @State private var showNewProjectAlert = false
    @State private var newProjectName = ""
    @State private var projects: [FocusTask] = []
    @State private var lists: [FocusTask] = []

    // Toast state
    @State private var toastMessage = ""
    @State private var showToast = false

    private var selectedCount: Int {
        switch source {
        case .project(_, let vm): return vm.selectedContentTaskIds.count
        case .list(_, let vm): return vm.selectedContentItemIds.count
        }
    }

    private var sourceId: UUID {
        switch source {
        case .project(let id, _): return id
        case .list(let id, _): return id
        }
    }

    private var sections: [FocusTask] {
        switch source {
        case .project(let id, let vm):
            let tasks = vm.projectTasksMap[id] ?? []
            return tasks
                .filter { $0.isSection && !$0.isCompleted && $0.parentTaskId == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
        case .list(let id, let vm):
            let items = vm.itemsMap[id] ?? []
            return items
                .filter { $0.isSection && !$0.isCompleted }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private var hasSections: Bool { !sections.isEmpty }

    private var otherProjects: [FocusTask] {
        projects.filter { $0.id != sourceId }
    }

    private var otherLists: [FocusTask] {
        lists.filter { $0.id != sourceId }
    }

    var body: some View {
        ZStack {
            DrawerContainer(
                title: "Move \(selectedCount) Item\(selectedCount == 1 ? "" : "s")",
                leadingButton: .cancel { dismiss() }
            ) {
                ScrollView {
                    VStack(spacing: AppStyle.Spacing.comfortable) {
                        // Inbox
                        inboxCard

                        // Sections (project source only)
                        if hasSections {
                            sectionCard
                        }

                        // Projects
                        projectCard

                        // Lists
                        listCard
                    }
                    .padding(.bottom, AppStyle.Spacing.page)
                }
                .background(.clear)
                .task {
                    let repo = TaskRepository(supabase: SupabaseClientManager.shared.client)
                    do {
                        projects = try await repo.fetchProjects(isCleared: false, isCompleted: false)
                    } catch { }
                    do {
                        lists = try await repo.fetchTasks(ofType: .list, isCleared: false, isCompleted: false)
                    } catch { }
                }
                .alert("New Project", isPresented: $showNewProjectAlert) {
                    TextField("Project name", text: $newProjectName)
                    Button("Cancel", role: .cancel) { newProjectName = "" }
                    Button("Create") {
                        let name = newProjectName
                        newProjectName = ""
                        handleNewProject(name: name)
                    }
                }
            }
            .allowsHitTesting(!showToast)

            // Toast overlay
            if showToast {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                Text(toastMessage)
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppStyle.Spacing.section)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Inbox Card

    private var inboxCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            moveRow(icon: "tray", title: "Inbox") {
                performMove(message: "Moved to Inbox") {
                    await moveToInbox()
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
    }

    // MARK: - Section Card

    private var sectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Section")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            moveRow(icon: "minus.circle", title: "No section") {
                performMove(message: "Moved to no section") {
                    await moveToSection(nil)
                }
            }

            ForEach(sections) { section in
                Divider()
                    .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                moveRow(icon: "rectangle.split.3x1", title: section.title.isEmpty ? "Untitled section" : section.title) {
                    performMove(message: "Moved to section") {
                        await moveToSection(section.id)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
    }

    // MARK: - Project Card

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Project")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            if otherProjects.isEmpty {
                Text("No projects")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
            } else {
                ForEach(Array(otherProjects.enumerated()), id: \.element.id) { index, project in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                    }
                    moveRow(customImage: "ProjectIcon", title: project.title) {
                        performMove(message: "Moved to project") {
                            await moveToProject(project.id)
                        }
                    }
                }
            }

            Divider()
                .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)

            Button {
                showNewProjectAlert = true
            } label: {
                HStack(spacing: AppStyle.Spacing.medium) {
                    Image(systemName: "plus")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                        .frame(width: AppStyle.Layout.pillButton)
                    Text("New Project")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.comfortable)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - List Card

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("List")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            if otherLists.isEmpty {
                Text("No lists")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
            } else {
                ForEach(Array(otherLists.enumerated()), id: \.element.id) { index, list in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                    }
                    moveRow(icon: "checklist", title: list.title) {
                        performMove(message: "Moved to list") {
                            await moveToList(list.id)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Shared Row

    private func moveRow(icon: String? = nil, customImage: String? = nil, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.medium) {
                if let customImage {
                    Image(customImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.pillButton)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.inter(.body))
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.pillButton)
                }
                Text(title)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.vertical, AppStyle.Spacing.comfortable)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func moveToSection(_ sectionId: UUID?) async {
        switch source {
        case .project(let id, let vm):
            await vm.batchMoveContentTasksToSection(sectionId: sectionId, projectId: id)
        case .list(let id, let vm):
            await vm.batchMoveContentItemsToSection(sectionId: sectionId, listId: id)
        }
    }

    private func moveToInbox() async {
        switch source {
        case .project(let srcId, let vm):
            await vm.batchMoveContentTasksToInbox(sourceProjectId: srcId)
        case .list(let srcId, let vm):
            await vm.batchMoveContentItemsToInbox(sourceListId: srcId)
        }
    }

    private func moveToProject(_ projectId: UUID) async {
        switch source {
        case .project(let srcId, let vm):
            await vm.batchMoveContentTasksToProject(targetProjectId: projectId, sourceProjectId: srcId)
        case .list(let srcId, let vm):
            await vm.batchMoveContentItemsToProject(projectId: projectId, sourceListId: srcId)
        }
    }

    private func moveToList(_ listId: UUID) async {
        switch source {
        case .project(let srcId, let vm):
            await vm.batchMoveContentTasksToList(targetListId: listId, sourceProjectId: srcId)
        case .list(let srcId, let vm):
            await vm.batchMoveContentItemsToList(targetListId: listId, sourceListId: srcId)
        }
    }

    private func handleNewProject(name: String) {
        switch source {
        case .project(let srcId, let vm):
            _Concurrency.Task {
                guard let newId = await vm.saveNewProject(
                    title: name,
                    categoryId: nil,
                    draftTasks: []
                ) else { return }
                await vm.batchMoveContentTasksToProject(targetProjectId: newId, sourceProjectId: srcId)
                dismiss()
            }
        case .list(let srcId, let vm):
            _Concurrency.Task {
                guard let projectId = await vm.createProjectAndReturnId(title: name) else { return }
                await vm.batchMoveContentItemsToProject(projectId: projectId, sourceListId: srcId)
                dismiss()
            }
        }
    }

    private func performMove(message: String, action: @escaping () async -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(AppStyle.Anim.modeSwitch) {
            toastMessage = message
            showToast = true
        }
        _Concurrency.Task {
            await action()
            try? await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        }
    }
}
