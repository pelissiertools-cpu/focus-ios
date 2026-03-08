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
    @State private var showingAddBar = false

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            List {
                HStack(spacing: AppStyle.Spacing.medium) {
                    Image(systemName: "folder")
                        .font(.inter(.title2, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Projects")
                        .pageTitleStyle()
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.section, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: AppStyle.Spacing.page, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                } else if viewModel.projects.isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No projects yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Your projects will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.comfortable, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
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
                            .listRowInsets(AppStyle.Insets.row)
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
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.reorderProjects(from: from, to: to)
                    }

                }

                Color.clear
                    .frame(height: projectsViewModel.isEditMode ? 100 : AppStyle.Spacing.page)
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

            if !showingAddBar && !projectsViewModel.isEditMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.title2, weight: .semiBold))
                                .foregroundColor(.white)
                                .frame(width: AppStyle.Layout.fab, height: AppStyle.Layout.fab)
                                .glassEffect(.regular.tint(.charcoal).interactive(), in: .circle)
                                .shadow(radius: 4, y: 2)
                        }
                        .accessibilityLabel("Add project")
                        .padding(.trailing, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.page)
                    }
                }
            }

            if showingAddBar {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(50)

                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = false
                            }
                        }

                    AddProjectBar(
                        projectsViewModel: projectsViewModel,
                        onSaved: {
                            _Concurrency.Task {
                                await viewModel.fetchProjects()
                                await projectsViewModel.fetchProjects()
                            }
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = false
                            }
                        }
                    )
                    .padding(.bottom, AppStyle.Spacing.compact)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(51)
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
                        .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(projectsViewModel.isEditMode ? "Cancel" : "Back")
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
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
    }

    // MARK: - Project Row

    @ViewBuilder
    private func projectRow(_ project: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if projectsViewModel.isEditMode {
                Image(systemName: projectsViewModel.selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(projectsViewModel.selectedProjectIds.contains(project.id) ? .appRed : .secondary)
            }

            ProjectProgressRing(
                completed: projectsViewModel.taskProgress(for: project.id).completed,
                total: projectsViewModel.taskProgress(for: project.id).total,
                size: AppStyle.Layout.pillButton
            )

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

        }
        .padding(.vertical, AppStyle.Spacing.medium)
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
