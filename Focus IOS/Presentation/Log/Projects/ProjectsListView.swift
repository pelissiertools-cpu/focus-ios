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

    // Drag state
    @State private var draggingProjectId: UUID?
    @State private var dragFingerY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var dragReorderAdjustment: CGFloat = 0
    @State private var lastReorderTime: Date = .distantPast
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var showClearCompletedConfirmation = false

    init(viewModel: ProjectsViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading projects...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.projects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .padding(.top, 44)
        .sheet(item: $viewModel.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: viewModel)
                .drawerStyle()
        }
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
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
                .drawerStyle()
        }
        // Batch commit sheet
        .sheet(isPresented: $viewModel.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: viewModel)
                .drawerStyle()
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
                .font(.sf(size: 60))
                .foregroundColor(.secondary)

            Text("No Projects Yet")
                .font(.sf(.title2, weight: .semibold))

            Text("Tap the + button to create your first project")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Uncompleted projects — reorderable
                ForEach(viewModel.filteredProjects) { project in
                    let isDragging = draggingProjectId == project.id

                    ProjectCard(
                        project: project,
                        viewModel: viewModel,
                        onDragChanged: viewModel.isEditMode ? nil : { value in handleProjectDrag(project.id, value) },
                        onDragEnded: viewModel.isEditMode ? nil : { handleProjectDragEnd() }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowFramePreference.self,
                                value: [project.id: geo.frame(in: .named("projectList"))]
                            )
                        }
                    )
                    .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                    .scaleEffect(isDragging ? 1.03 : 1.0)
                    .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                    .zIndex(isDragging ? 1 : 0)
                    .transaction { t in
                        if isDragging { t.animation = nil }
                    }
                    .id("active-\(project.id)")
                }

                // Done section
                if !viewModel.isEditMode && !viewModel.completedProjects.isEmpty {
                    doneSectionHeader

                    if !viewModel.isDoneCollapsed {
                        ForEach(viewModel.completedProjects) { project in
                            ProjectCard(project: project, viewModel: viewModel)
                                .id("done-\(project.id)")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 100)
            .onPreferenceChange(RowFramePreference.self) { frames in
                rowFrames = frames
            }
        }
        .coordinateSpace(name: "projectList")
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchProjects()
                    continuation.resume()
                }
            }
        }
    }

    private var doneSectionHeader: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleDoneCollapsed()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isDoneCollapsed ? "chevron.right" : "chevron.down")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)

                    Text("Completed")
                        .font(.sf(.subheadline, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("(\(viewModel.completedProjects.count))")
                        .font(.sf(.subheadline))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !viewModel.isDoneCollapsed {
                Button {
                    showClearCompletedConfirmation = true
                } label: {
                    Text("Clear list")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .alert("Clear completed projects?", isPresented: $showClearCompletedConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.clearCompletedProjects()
                }
            }
        } message: {
            Text("This will permanently delete \(viewModel.completedProjects.count) completed project\(viewModel.completedProjects.count == 1 ? "" : "s").")
        }
    }

    // MARK: - Drag Handlers

    private func handleProjectDrag(_ projectId: UUID, _ value: DragGesture.Value) {
        if draggingProjectId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingProjectId = projectId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        let projects = viewModel.filteredProjects
        guard let currentIdx = projects.firstIndex(where: { $0.id == projectId }) else { return }

        for (idx, other) in projects.enumerated() where other.id != projectId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderProject(droppedId: projectId, targetId: other.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleProjectDragEnd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingProjectId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
        }
        lastReorderTime = .distantPast
    }
}

#Preview {
    ProjectsListView(viewModel: ProjectsViewModel(authService: AuthService()))
        .environmentObject(AuthService())
}
