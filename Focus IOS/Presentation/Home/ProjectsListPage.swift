//
//  ProjectsListPage.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct ProjectsListPage: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var projectToDelete: FocusTask?
    @State private var selectedProject: FocusTask?
    @State private var editingSectionId: UUID?

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            List {
                Text("Projects")
                    .pageTitleStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                } else if viewModel.projects.isEmpty {
                    VStack(spacing: 4) {
                        Text("No projects yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Your projects will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                } else {
                    ForEach(viewModel.projects.filter { !$0.isCompleted && !$0.isCleared }) { item in
                        if item.isSection {
                            SectionDividerRow(
                                section: item,
                                editingSectionId: $editingSectionId,
                                onRename: { section, newTitle in
                                    await viewModel.renameSection(section, newTitle: newTitle)
                                },
                                onDelete: { section in
                                    await viewModel.deleteSection(section)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    _Concurrency.Task {
                                        await viewModel.deleteSection(item)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else {
                            projectRow(item)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.reorderProjects(from: from, to: to)
                    }

                }

                Color.clear
                    .frame(height: projectsViewModel.isEditMode ? 100 : 20)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })

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
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
            )
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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

                        Button {
                            _Concurrency.Task {
                                guard let userId = authService.currentUser?.id else { return }
                                if let section = await viewModel.createSection(type: .project, userId: userId) {
                                    editingSectionId = section.id
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

            Image(systemName: "folder")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

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
                ContextMenuItems.pinButton(isPinned: project.isPinned) {
                    _Concurrency.Task { await viewModel.togglePin(project) }
                }
                Divider()
                ContextMenuItems.deleteButton { projectToDelete = project }
            }
        }
    }
}
