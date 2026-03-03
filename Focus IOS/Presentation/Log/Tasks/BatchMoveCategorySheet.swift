//
//  BatchMoveCategorySheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct BatchMoveCategorySheet<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    var onMoveToProject: ((UUID) async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var projects: [FocusTask] = []

    var body: some View {
        DrawerContainer(
            title: "Move \(viewModel.selectedCount) Items",
            leadingButton: .cancel { dismiss() }
        ) {
            VStack(spacing: 0) {
                List {
                    SwiftUI.Section("Category") {
                        Button {
                            _Concurrency.Task {
                                await viewModel.batchMoveToCategory(nil)
                                dismiss()
                            }
                        } label: {
                            Label("None", systemImage: "xmark.circle")
                                .foregroundColor(.primary)
                        }

                        ForEach(viewModel.categories) { category in
                            Button {
                                _Concurrency.Task {
                                    await viewModel.batchMoveToCategory(category.id)
                                    dismiss()
                                }
                            } label: {
                                Text(category.name)
                                    .foregroundColor(.primary)
                            }
                        }

                        Button {
                            showingNewCategoryAlert = true
                        } label: {
                            Label("New Category", systemImage: "plus")
                                .foregroundColor(.appRed)
                        }
                    }

                    if onMoveToProject != nil {
                        SwiftUI.Section("Project") {
                            ForEach(projects) { project in
                                Button {
                                    _Concurrency.Task {
                                        await onMoveToProject?(project.id)
                                        dismiss()
                                    }
                                } label: {
                                    Label(project.title, systemImage: "folder")
                                        .foregroundColor(.primary)
                                }
                            }

                            if projects.isEmpty {
                                Text("No projects")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let name = newCategoryName
                    newCategoryName = ""
                    _Concurrency.Task {
                        await viewModel.createCategory(name: name)
                        if let created = viewModel.categories.last {
                            await viewModel.batchMoveToCategory(created.id)
                        }
                        dismiss()
                    }
                }
            }
            .task {
                if onMoveToProject != nil {
                    do {
                        let repo = TaskRepository(supabase: SupabaseClientManager.shared.client)
                        projects = try await repo.fetchProjects()
                    } catch { }
                }
            }
        }
    }
}
