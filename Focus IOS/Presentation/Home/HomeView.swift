//
//  HomeView.swift
//  Focus IOS
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @State private var showSettings = false

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

                    // MARK: - Todos Header
                    Text("Todos")
                        .font(.inter(size: 28, weight: .regular))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    // MARK: - Menu Items
                    ForEach(HomeMenuItem.allCases) { item in
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
                        ForEach(viewModel.projects) { project in
                            Button {
                                viewModel.selectedProject = project
                            } label: {
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
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // MARK: - Lists Header
                    Text("Lists")
                        .font(.inter(.headline, weight: .bold))
                        .foregroundColor(.appRed)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
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
                        ForEach(viewModel.lists) { list in
                            Button {
                                viewModel.selectedList = list
                            } label: {
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
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 120)
            }
            .navigationDestination(item: $viewModel.selectedMenuItem) { menuItem in
                if menuItem == .archive {
                    ArchiveView()
                } else if menuItem == .unassign {
                    UnassignedView()
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
            .task {
                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    await viewModel.fetchProjects()
                }
                if viewModel.lists.isEmpty {
                    await viewModel.fetchLists()
                }
            }
            .onChange(of: viewModel.selectedMenuItem) { _, newValue in
                if newValue == nil {
                    _Concurrency.Task {
                        await viewModel.fetchProjects()
                        await viewModel.fetchLists()
                    }
                }
            }
            .onChange(of: viewModel.selectedProject) { _, newValue in
                if newValue == nil {
                    _Concurrency.Task { await viewModel.fetchProjects() }
                }
            }
            .onChange(of: viewModel.selectedList) { _, newValue in
                if newValue == nil {
                    _Concurrency.Task { await viewModel.fetchLists() }
                }
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
