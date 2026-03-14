//
//  ArchiveView.swift
//  Focus IOS
//

import SwiftUI

struct ArchiveView: View {
    @StateObject private var viewModel = ArchiveViewModel()
    @StateObject private var projectsViewModel: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProject: FocusTask?

    init(authService: AuthService) {
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
        Color.appBackground.ignoresSafeArea()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Title
                HStack(spacing: AppStyle.Spacing.compact) {
                    Image(systemName: "archivebox")
                        .font(.helveticaNeue(size: 15, weight: .medium))
                        .foregroundColor(.appText)
                        .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                        .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                    Text("Completed")
                        .pageTitleStyle()
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.top, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.tiny)

                // Count + Clear
                if viewModel.totalCount > 0 {
                    HStack(spacing: 0) {
                        Text("\(viewModel.totalCount) Completed")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)

                        Text("  ·  ")
                            .foregroundColor(.secondary)

                        Button {
                            viewModel.showClearConfirmation = true
                        } label: {
                            Text("Clear")
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(.focusBlue)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, AppStyle.Spacing.page)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.sections.isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No completed items")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Completed tasks, projects, and lists will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(viewModel.sections) { section in
                        ArchiveSectionHeader(title: section.title)

                        ForEach(section.tasks) { task in
                            ArchiveItemRow(
                                task: task,
                                isEditMode: viewModel.isEditMode,
                                isSelected: viewModel.selectedIds.contains(task.id),
                                onToggleSelection: { viewModel.toggleSelection(task.id) },
                                onUncomplete: {
                                    _Concurrency.Task { await viewModel.uncompleteTask(task) }
                                },
                                onNavigate: task.type == .project ? {
                                    navigateToProject(task)
                                } : nil
                            )
                            .padding(.horizontal, AppStyle.Insets.nestedRow.leading)
                        }
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .navigationDestination(item: $selectedProject) { project in
            ProjectContentView(project: project, viewModel: projectsViewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.isEditMode {
                    Button {
                        viewModel.exitEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isEditMode {
                    Button {
                        if viewModel.allSelected {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
                        }
                    } label: {
                        Text(viewModel.allSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            viewModel.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isEditMode && !viewModel.selectedIds.isEmpty {
                Button {
                    viewModel.showDeleteConfirmation = true
                } label: {
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Image(systemName: "trash")
                        Text("Delete \(viewModel.selectedIds.count)")
                    }
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, AppStyle.Spacing.expanded)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                    .glassEffect(.regular, in: .capsule)
                    .fabShadow()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
        }
        .alert("Delete \(viewModel.selectedIds.count) item\(viewModel.selectedIds.count == 1 ? "" : "s")?",
               isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteSelected()
                }
            }
        } message: {
            Text("This will permanently delete the selected items.")
        }
        .alert("Clear all completed items?",
               isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.clearAll()
                }
            }
        } message: {
            Text("This will permanently delete all \(viewModel.totalCount) completed items.")
        }
        .task {
            await viewModel.fetchCompletedItems()
        }
        } // ZStack
    }

    private func navigateToProject(_ project: FocusTask) {
        _Concurrency.Task {
            await projectsViewModel.fetchProjects()
            // Ensure cleared projects are findable for content display
            if !projectsViewModel.projects.contains(where: { $0.id == project.id }) {
                projectsViewModel.projects.append(project)
            }
            await projectsViewModel.fetchProjectTasks(for: project.id)
            selectedProject = project
        }
    }
}

// MARK: - Archive Section Header

private struct ArchiveSectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, AppStyle.Spacing.small)
            .padding(.horizontal, AppStyle.Spacing.comfortable)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
    }
}

// MARK: - Archive Item Row

private struct ArchiveItemRow: View {
    let task: FocusTask
    let isEditMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onUncomplete: () -> Void
    let onNavigate: (() -> Void)?

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            } else {
                Button {
                    onUncomplete()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.todayBadge)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.focusBlue)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(task.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if task.type == .project {
                Image("ProjectIcon")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(.secondary)
            } else if task.type == .list {
                Image(systemName: "checklist")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onToggleSelection()
            } else if let onNavigate {
                onNavigate()
            }
        }
    }
}
