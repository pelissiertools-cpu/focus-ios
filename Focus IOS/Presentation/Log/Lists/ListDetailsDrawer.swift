//
//  ListDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ListDetailsDrawer: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    @State private var listTitle: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""
    @State private var showingCommitmentSheet = false
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss

    init(list: FocusTask, viewModel: ListsViewModel) {
        self.list = list
        self.viewModel = viewModel
        _listTitle = State(initialValue: list.title)
    }

    var body: some View {
        DrawerContainer(
            title: "List Details",
            leadingButton: .done {
                saveTitle()
                dismiss()
            }
        ) {
            SwiftUI.List {
                DrawerTitleSection(
                    placeholder: "List title",
                    title: $listTitle,
                    onSubmit: saveTitle
                )

                SwiftUI.Section("Statistics") {
                    let items = viewModel.itemsMap[list.id] ?? []
                    let completed = items.filter { $0.isCompleted }.count
                    DrawerStatsRow(icon: "checklist", text: "\(completed)/\(items.count) items done")
                }

                SwiftUI.Section("Category") {
                    DrawerCategoryMenu(
                        currentCategoryId: list.categoryId,
                        categories: viewModel.categories,
                        onSelect: { categoryId in
                            _Concurrency.Task {
                                await viewModel.moveTaskToCategory(list, categoryId: categoryId)
                            }
                        },
                        onCreateNew: { showingNewCategory = true }
                    )
                }

                SwiftUI.Section {
                    Button {
                        showingCommitmentSheet = true
                    } label: {
                        Label("Commit to Focus", systemImage: "arrow.right.circle")
                    }
                }

                DrawerDeleteSection(title: "Delete List") {
                    _Concurrency.Task {
                        await viewModel.deleteList(list)
                        dismiss()
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let name = newCategoryName
                    newCategoryName = ""
                    _Concurrency.Task {
                        await viewModel.createCategoryAndMove(name: name, task: list)
                    }
                }
            }
            .sheet(isPresented: $showingCommitmentSheet, onDismiss: {
                _Concurrency.Task { await viewModel.fetchCommittedTaskIds() }
            }) {
                CommitmentSelectionSheet(task: list, focusViewModel: focusViewModel)
            }
        }
    }

    private func saveTitle() {
        let trimmed = listTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != list.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(list, newTitle: trimmed)
        }
    }
}
