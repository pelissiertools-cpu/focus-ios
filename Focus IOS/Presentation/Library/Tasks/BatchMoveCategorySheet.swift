//
//  BatchMoveCategorySheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct BatchMoveCategorySheet: View {
    @ObservedObject var viewModel: TaskListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationView {
            List {
                Button {
                    Task {
                        await viewModel.batchMoveToCategory(nil)
                        dismiss()
                    }
                } label: {
                    Label("None", systemImage: "xmark.circle")
                        .foregroundColor(.primary)
                }

                ForEach(viewModel.categories) { category in
                    Button {
                        Task {
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
                        .foregroundColor(.blue)
                }
            }
            .navigationTitle("Move \(viewModel.selectedCount) Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let name = newCategoryName
                    newCategoryName = ""
                    Task {
                        await viewModel.createCategory(name: name)
                        if let created = viewModel.categories.last {
                            await viewModel.batchMoveToCategory(created.id)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
