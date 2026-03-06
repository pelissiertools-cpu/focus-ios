//
//  ProjectsListPage.swift
//  Focus IOS
//

import SwiftUI

struct ProjectsListPage: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var projectToDelete: FocusTask?
    @State private var selectedProject: FocusTask?

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Projects")
                        .font(.inter(.title2, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    } else if viewModel.projects.isEmpty {
                        Text("No projects yet")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        ForEach(viewModel.projects) { project in
                            projectRow(project)
                        }
                    }
                }
                .padding(.bottom, projectsViewModel.isEditMode ? 100 : 20)
            }

            if projectsViewModel.isEditMode {
                EditModeActionBar(viewModel: projectsViewModel)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationDestination(item: $selectedProject) { project in
            ProjectContentView(project: project, viewModel: projectsViewModel)
        }
        .sheet(item: $projectsViewModel.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsViewModel)
                .drawerStyle()
        }
        .sheet(item: $projectsViewModel.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(task: task, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $projectsViewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: projectsViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $projectsViewModel.showBatchScheduleSheet) {
            BatchScheduleSheet(viewModel: projectsViewModel)
                .drawerStyle()
        }
        .task {
            if viewModel.projects.isEmpty && !viewModel.isLoading {
                await viewModel.fetchProjects(showLoading: true)
            }
            await projectsViewModel.fetchProjects()
        }
        .onChange(of: projectsViewModel.selectedProjectForDetails) { _, newValue in
            if newValue == nil {
                _Concurrency.Task { await viewModel.fetchProjects() }
            }
        }
        .alert("Delete Project", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    _Concurrency.Task { await viewModel.deleteProject(project) }
                }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(projectToDelete?.title ?? "")\"?")
        }
        .alert("Delete Selected", isPresented: $projectsViewModel.showBatchDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await projectsViewModel.batchDeleteProjects()
                    await viewModel.fetchProjects()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(projectsViewModel.selectedCount) project\(projectsViewModel.selectedCount == 1 ? "" : "s")?")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if projectsViewModel.isEditMode {
                        projectsViewModel.exitEditMode()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: projectsViewModel.isEditMode ? "xmark" : "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .contentShape(Circle())
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if projectsViewModel.isEditMode {
                    Button {
                        if projectsViewModel.allUncompletedSelected {
                            projectsViewModel.deselectAll()
                        } else {
                            projectsViewModel.selectAllUncompleted()
                        }
                    } label: {
                        Text(projectsViewModel.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            projectsViewModel.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
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
        }
    }

    // MARK: - Project Row

    @ViewBuilder
    private func projectRow(_ project: FocusTask) -> some View {
        HStack(spacing: 12) {
            if projectsViewModel.isEditMode {
                Image(systemName: projectsViewModel.selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(projectsViewModel.selectedProjectIds.contains(project.id) ? .appRed : .secondary)
            }

            ProjectIconShape()
                .frame(width: 24, height: 24)
                .foregroundColor(.secondary)

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if !projectsViewModel.isEditMode {
                Image(systemName: "chevron.right")
                    .font(.inter(size: 12, weight: .semiBold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if projectsViewModel.isEditMode {
                projectsViewModel.toggleProjectSelection(project.id)
            } else {
                selectedProject = project
            }
        }
        .contextMenu {
            if !projectsViewModel.isEditMode {
                ContextMenuItems.editButton { projectsViewModel.selectedProjectForDetails = project }
                ContextMenuItems.scheduleButton { projectsViewModel.selectedTaskForSchedule = project }
                Divider()
                ContextMenuItems.deleteButton { projectToDelete = project }
            }
        }
    }
}
