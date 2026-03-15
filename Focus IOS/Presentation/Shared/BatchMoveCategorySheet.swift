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
    var onMoveToList: ((UUID) async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var projects: [FocusTask] = []
    @State private var lists: [FocusTask] = []

    // Toast state
    @State private var toastMessage = ""
    @State private var showToast = false

    var body: some View {
        ZStack {
        DrawerContainer(
            title: "Move \(viewModel.selectedCount) Items",
            leadingButton: .cancel { dismiss() }
        ) {
            List {
                SwiftUI.Section("Category") {
                    Button {
                        performMove(message: "Moved to Uncategorized") {
                            await viewModel.batchMoveToCategory(nil)
                        }
                    } label: {
                        Label("None", systemImage: "xmark.circle")
                            .foregroundColor(.primary)
                    }

                    ForEach(viewModel.categories) { category in
                        Button {
                            performMove(message: "Moved to \(category.name)") {
                                await viewModel.batchMoveToCategory(category.id)
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
                        if projects.isEmpty {
                            Text("No projects")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(projects) { project in
                                HStack(spacing: 10) {
                                    Image("ProjectIcon")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.primary)
                                    Text(project.title)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let moveToProject = onMoveToProject
                                    let id = project.id
                                    performMove(message: "Moved to project") {
                                        await moveToProject?(id)
                                    }
                                }
                            }
                        }
                    }
                }

                if onMoveToList != nil {
                    SwiftUI.Section("List") {
                        if lists.isEmpty {
                            Text("No lists")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(lists) { list in
                                HStack(spacing: 10) {
                                    Image(systemName: "list.bullet")
                                        .foregroundColor(.primary)
                                    Text(list.title)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let moveToList = onMoveToList
                                    let id = list.id
                                    performMove(message: "Moved to list") {
                                        await moveToList?(id)
                                    }
                                }
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
                    performMove(message: "Moved to \(name)") {
                        await viewModel.createCategory(name: name)
                        if let created = viewModel.categories.last {
                            await viewModel.batchMoveToCategory(created.id)
                        }
                    }
                }
            }
            .task {
                let repo = TaskRepository(supabase: SupabaseClientManager.shared.client)
                if onMoveToProject != nil {
                    do {
                        projects = try await repo.fetchProjects(isCleared: false, isCompleted: false)
                    } catch { }
                }
                if onMoveToList != nil {
                    do {
                        lists = try await repo.fetchTasks(ofType: .list, isCleared: false, isCompleted: false)
                    } catch { }
                }
            }
        }
        .allowsHitTesting(!showToast)

            // Toast overlay
            if showToast {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                Text(toastMessage)
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppStyle.Spacing.section)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func performMove(message: String, action: @escaping () async -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(AppStyle.Anim.modeSwitch) {
            toastMessage = message
            showToast = true
        }
        _Concurrency.Task {
            await action()
            try? await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        }
    }
}
