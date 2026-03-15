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
                ScrollView {
                    VStack(spacing: AppStyle.Spacing.comfortable) {
                        // ─── CATEGORY ───
                        categoryCard

                        // ─── PROJECT ───
                        if onMoveToProject != nil {
                            projectCard
                        }

                        // ─── LIST ───
                        if onMoveToList != nil {
                            listCard
                        }
                    }
                    .padding(.bottom, AppStyle.Spacing.page)
                }
                .background(.clear)
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

    // MARK: - Category Card

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Category")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            moveRow(icon: "xmark.circle", title: "None") {
                performMove(message: "Moved to Uncategorized") {
                    await viewModel.batchMoveToCategory(nil)
                }
            }

            ForEach(viewModel.categories) { category in
                Divider()
                    .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                moveRow(title: category.name) {
                    performMove(message: "Moved to \(category.name)") {
                        await viewModel.batchMoveToCategory(category.id)
                    }
                }
            }

            Divider()
                .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)

            Button {
                showingNewCategoryAlert = true
            } label: {
                HStack(spacing: AppStyle.Spacing.medium) {
                    Image(systemName: "plus")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                        .frame(width: AppStyle.Layout.pillButton)
                    Text("New Category")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.comfortable)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
    }

    // MARK: - Project Card

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Project")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            if projects.isEmpty {
                Text("No projects")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
            } else {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                    }
                    moveRow(customImage: "ProjectIcon", title: project.title) {
                        let moveToProject = onMoveToProject
                        performMove(message: "Moved to project") {
                            await moveToProject?(project.id)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - List Card

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("List")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            if lists.isEmpty {
                Text("No lists")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
            } else {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppStyle.Spacing.section + AppStyle.Spacing.medium + AppStyle.Layout.pillButton)
                    }
                    moveRow(icon: "checklist", title: list.title) {
                        let moveToList = onMoveToList
                        performMove(message: "Moved to list") {
                            await moveToList?(list.id)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Shared Row

    private func moveRow(icon: String? = nil, customImage: String? = nil, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.medium) {
                if let customImage {
                    Image(customImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.pillButton)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.inter(.body))
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.pillButton)
                }
                Text(title)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.vertical, AppStyle.Spacing.comfortable)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
