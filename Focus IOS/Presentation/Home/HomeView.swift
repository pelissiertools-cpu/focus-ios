//
//  HomeView.swift
//  Focus IOS
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @State private var showSettings = false
    @State private var projectToDelete: FocusTask?
    @State private var listToDelete: FocusTask?

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: AuthService()))
        _listsViewModel = StateObject(wrappedValue: ListsViewModel(authService: AuthService()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: - Top Bar
                    HStack {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "person")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
                        }

                        Spacer()

                        Button(action: { /* search — placeholder */ }) {
                            Image(systemName: "magnifyingglass")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    // MARK: - Menu Items (Today, Scheduled)
                    ForEach([HomeMenuItem.today, .assign], id: \.self) { item in
                        homeMenuButton(item)
                    }

                    // MARK: - Divider
                    Rectangle()
                        .fill(Color.appRed.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // MARK: - Menu Items (Backlog, Braindump)
                    ForEach([HomeMenuItem.unassign, .braindump], id: \.self) { item in
                        homeMenuButton(item)
                    }

                    // MARK: - Divider
                    Rectangle()
                        .fill(Color.appRed.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // MARK: - Menu Items (Archive)
                    ForEach([HomeMenuItem.archive], id: \.self) { item in
                        homeMenuButton(item)
                    }

                    // MARK: - Projects Header
                    Text("Projects")
                        .font(.inter(.headline, weight: .bold))
                        .foregroundColor(.appRed)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    Rectangle()
                        .fill(Color.appRed.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    // MARK: - Project Rows
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
                        List {
                            ForEach(viewModel.projects) { project in
                                HomeProjectRow(
                                    project: project,
                                    onTap: { viewModel.selectedProject = project },
                                    onEdit: { projectsViewModel.selectedProjectForDetails = project },
                                    onSchedule: { projectsViewModel.selectedTaskForSchedule = project },
                                    onRequestDelete: { projectToDelete = project }
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onMove { from, to in
                                viewModel.reorderProjects(from: from, to: to)
                            }
                        }
                        .listStyle(.plain)
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: CGFloat(viewModel.projects.count) * 56)
                    }

                    // MARK: - Quick Lists Header
                    Text("Quick Lists")
                        .font(.inter(.headline, weight: .bold))
                        .foregroundColor(.appRed)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    Rectangle()
                        .fill(Color.appRed.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    // MARK: - List Rows
                    if viewModel.lists.isEmpty {
                        Text("No lists yet")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        List {
                            ForEach(viewModel.lists) { list in
                                HomeListRow(
                                    list: list,
                                    onTap: { viewModel.selectedList = list },
                                    onEdit: { listsViewModel.selectedListForDetails = list },
                                    onSchedule: { listsViewModel.selectedItemForSchedule = list },
                                    onRequestDelete: { listToDelete = list }
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onMove { from, to in
                                viewModel.reorderLists(from: from, to: to)
                            }
                        }
                        .listStyle(.plain)
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: CGFloat(viewModel.lists.count) * 56)
                    }
                }
                .padding(.bottom, 120)
            }
            .navigationDestination(item: $viewModel.selectedMenuItem) { menuItem in
                if menuItem == .archive {
                    ArchiveView()
                } else if menuItem == .unassign {
                    BacklogView()
                } else if menuItem == .assign {
                    ScheduledView()
                } else {
                    HomePlaceholderPage(title: menuItem.rawValue)
                }
            }
            .navigationDestination(item: $viewModel.selectedProject) { project in
                ProjectContentView(project: project, viewModel: projectsViewModel)
            }
            .navigationDestination(item: $viewModel.selectedList) { list in
                ListContentView(list: list, viewModel: listsViewModel)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationBarHidden(true)
            // Project edit drawer
            .sheet(item: $projectsViewModel.selectedProjectForDetails) { project in
                ProjectDetailsDrawer(project: project, viewModel: projectsViewModel)
                    .drawerStyle()
            }
            // Project schedule sheet
            .sheet(item: $projectsViewModel.selectedTaskForSchedule) { task in
                CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                    .drawerStyle()
            }
            // List edit drawer
            .sheet(item: $listsViewModel.selectedListForDetails) { list in
                ListDetailsDrawer(list: list, viewModel: listsViewModel)
                    .drawerStyle()
            }
            // List schedule sheet
            .sheet(item: $listsViewModel.selectedItemForSchedule) { item in
                CommitmentSelectionSheet(task: item, focusViewModel: focusViewModel)
                    .drawerStyle()
            }
            .task {
                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    await viewModel.fetchProjects(showLoading: true)
                }
                if viewModel.lists.isEmpty {
                    await viewModel.fetchLists()
                }
                // Pre-load categories for edit drawers
                await projectsViewModel.fetchProjects()
                await listsViewModel.fetchLists()
            }
            // Silently refresh after edit drawer dismissals (user may have renamed/modified)
            .onChange(of: projectsViewModel.selectedProjectForDetails) { _, newValue in
                if newValue == nil {
                    _Concurrency.Task { await viewModel.fetchProjects() }
                }
            }
            .onChange(of: listsViewModel.selectedListForDetails) { _, newValue in
                if newValue == nil {
                    _Concurrency.Task { await viewModel.fetchLists() }
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
            .alert("Delete List", isPresented: Binding(
                get: { listToDelete != nil },
                set: { if !$0 { listToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let list = listToDelete {
                        _Concurrency.Task { await viewModel.deleteList(list) }
                    }
                }
                Button("Cancel", role: .cancel) { listToDelete = nil }
            } message: {
                Text("Are you sure you want to delete \"\(listToDelete?.title ?? "")\"?")
            }
        }
    }

    private func homeMenuButton(_ item: HomeMenuItem) -> some View {
        Button {
            viewModel.selectedMenuItem = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 24)

                Text(item.rawValue)
                    .font(.inter(.body))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home Project Row

private struct HomeProjectRow: View {
    let project: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProjectIconShape()
                .frame(width: 24, height: 24)
                .foregroundColor(.secondary)

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Home List Row

private struct HomeListRow: View {
    let list: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Placeholder Page

private struct HomePlaceholderPage: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text(title)
                .font(.inter(.title2, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}
