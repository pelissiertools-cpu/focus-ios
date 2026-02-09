//
//  ProjectsListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct ProjectsListView: View {
    @ObservedObject var viewModel: ProjectsViewModel

    let searchText: String

    init(viewModel: ProjectsViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading projects...")
            } else if viewModel.projects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .padding(.top, 44)
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
        // Batch delete confirmation
        .alert("Delete \(viewModel.selectedCount) project\(viewModel.selectedCount == 1 ? "" : "s")?", isPresented: $viewModel.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.batchDeleteProjects() }
            }
        } message: {
            Text("This will permanently delete the selected projects and their commitments.")
        }
        // Batch move category sheet
        .sheet(isPresented: $viewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: viewModel)
        }
        // Batch commit sheet
        .sheet(isPresented: $viewModel.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: viewModel)
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
    ProjectsListView(viewModel: ProjectsViewModel(authService: AuthService()))
        .environmentObject(AuthService())
}
