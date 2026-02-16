//
//  BatchMoveCategorySheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct BatchMoveCategorySheet<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var selectedTab = 0

    var body: some View {
        DrawerContainer(
            title: "Move \(viewModel.selectedCount) Items",
            leadingButton: .cancel { dismiss() }
        ) {
            VStack(spacing: 0) {
                Picker("Move To", selection: $selectedTab) {
                    Text("Tasks").tag(0)
                    Text("Projects").tag(1)
                    Text("Lists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                List {
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
                            .foregroundColor(.blue)
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
        }
    }
}
