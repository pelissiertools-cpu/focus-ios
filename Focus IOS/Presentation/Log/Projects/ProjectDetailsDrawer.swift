//
//  ProjectDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ProjectDetailsDrawer: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var projectTitle: String
    @Environment(\.dismiss) private var dismiss

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
    }

    var body: some View {
        DrawerContainer(
            title: "Project Details",
            leadingButton: .done {
                saveTitle()
                dismiss()
            }
        ) {
            List {
                DrawerTitleSection(
                    placeholder: "Project title",
                    title: $projectTitle,
                    autoFocus: true
                )

                SwiftUI.Section("Statistics") {
                    let taskProg = viewModel.taskProgress(for: project.id)
                    let subtaskProg = viewModel.subtaskProgress(for: project.id)

                    DrawerStatsRow(icon: "checklist", text: "\(taskProg.completed)/\(taskProg.total) tasks completed")
                    DrawerStatsRow(icon: "list.bullet.indent", text: "\(subtaskProg.completed)/\(subtaskProg.total) subtasks completed")
                }

                DrawerDeleteSection(title: "Delete Project") {
                    _Concurrency.Task {
                        await viewModel.deleteProject(project)
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(project, newTitle: trimmed)
        }
    }
}
