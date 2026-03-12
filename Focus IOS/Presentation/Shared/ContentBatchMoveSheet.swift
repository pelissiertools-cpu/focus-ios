//
//  ContentBatchMoveSheet.swift
//  Focus IOS
//

import SwiftUI

struct ContentBatchMoveSheet: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let projectId: UUID
    @Environment(\.dismiss) private var dismiss

    private var sections: [FocusTask] {
        let tasks = viewModel.projectTasksMap[projectId] ?? []
        return tasks
            .filter { $0.isSection && !$0.isCompleted && $0.parentTaskId == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hasSections: Bool { !sections.isEmpty }

    private var otherProjects: [FocusTask] {
        viewModel.projects.filter { !$0.isCompleted && !$0.isCleared && $0.id != projectId }
    }

    private var selectedCount: Int { viewModel.selectedContentTaskIds.count }

    var body: some View {
        DrawerContainer(
            title: "Move \(selectedCount) Task\(selectedCount == 1 ? "" : "s")",
            leadingButton: .cancel { dismiss() }
        ) {
            VStack(spacing: 0) {
                List {
                    if hasSections {
                        SwiftUI.Section("Section") {
                            Button {
                                _Concurrency.Task {
                                    await viewModel.batchMoveContentTasksToSection(sectionId: nil, projectId: projectId)
                                    dismiss()
                                }
                            } label: {
                                Label("No section", systemImage: "minus.circle")
                                    .foregroundColor(.primary)
                            }

                            ForEach(sections) { section in
                                Button {
                                    _Concurrency.Task {
                                        await viewModel.batchMoveContentTasksToSection(sectionId: section.id, projectId: projectId)
                                        dismiss()
                                    }
                                } label: {
                                    Label(section.title.isEmpty ? "Untitled section" : section.title, systemImage: "rectangle.split.3x1")
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }

                    SwiftUI.Section("Project") {
                        ForEach(otherProjects) { project in
                            Button {
                                _Concurrency.Task {
                                    await viewModel.batchMoveContentTasksToProject(targetProjectId: project.id, sourceProjectId: projectId)
                                    dismiss()
                                }
                            } label: {
                                Label(project.title, systemImage: "folder")
                                    .foregroundColor(.primary)
                            }
                        }

                        if otherProjects.isEmpty {
                            Text("No other projects")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
