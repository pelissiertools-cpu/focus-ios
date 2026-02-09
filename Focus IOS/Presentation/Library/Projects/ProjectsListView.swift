//
//  ProjectsListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct ProjectsListView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: ProjectsViewModel

    let searchText: String

    // Category dropdown state
    @State private var showCategoryDropdown = false

    init(searchText: String = "") {
        self.searchText = searchText
        _viewModel = StateObject(wrappedValue: ProjectsViewModel(authService: AuthService()))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main content
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading projects...")
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }

                // FAB button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            viewModel.showingAddProject = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                                .shadow(radius: 4, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            .padding(.top, 44)

            // Filter pills row (floats on top)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ProjectCategoryFilterPill(viewModel: viewModel, showDropdown: $showCategoryDropdown)
                }
                .padding(.leading)
            }
            .padding(.top, 4)
            .zIndex(10)

            // Floating category dropdown
            if showCategoryDropdown {
                ProjectCategoryDropdownMenu(viewModel: viewModel, showDropdown: $showCategoryDropdown)
                    .zIndex(20)
            }
        }
        .sheet(isPresented: $viewModel.showingAddProject) {
            AddProjectSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel, categories: viewModel.categories)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .task {
            if viewModel.projects.isEmpty && !viewModel.isLoading {
                await viewModel.fetchProjects()
            }
        }
        .onAppear {
            viewModel.searchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Projects Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to create your first project")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredProjects) { project in
                    ProjectCard(project: project, viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }
}

#Preview {
    ProjectsListView()
        .environmentObject(AuthService())
}
