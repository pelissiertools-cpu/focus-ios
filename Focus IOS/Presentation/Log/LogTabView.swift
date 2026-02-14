//
//  LogTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct LogTabView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

    // Shared filter state
    @State private var showCategoryDropdown = false

    // Batch create alerts (Tasks tab only)
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // View models — owned here, passed to child views
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Picker row with search pill
                    HStack(spacing: 12) {
                        Picker("Log Type", selection: $selectedTab) {
                            Text("Tasks").tag(0)
                            Text("Lists").tag(1)
                            Text("Projects").tag(2)
                        }
                        .pickerStyle(.segmented)

                        searchPillButton
                    }
                    .padding()

                    // Tab content with shared controls overlay
                    ZStack(alignment: .topLeading) {
                        // Tab content — all views stay alive to preserve scroll/state
                        ZStack {
                            TasksListView(viewModel: taskListVM, searchText: searchText, isSearchFocused: .constant(false))
                                .opacity(selectedTab == 0 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 0)

                            ListsView(viewModel: listsVM, searchText: searchText)
                                .opacity(selectedTab == 1 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 1)

                            ProjectsListView(viewModel: projectsVM, searchText: searchText)
                                .opacity(selectedTab == 2 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 2)
                        }

                        // Shared filter bar (floats on top)
                        filterBar
                            .zIndex(10)

                        // Shared category dropdown overlay
                        categoryDropdown
                            .zIndex(20)

                        // Shared floating bottom area (FAB or EditModeActionBar)
                        floatingBottomArea
                            .opacity(isSearchActive ? 0 : 1)
                            .allowsHitTesting(!isSearchActive)
                            .animation(.none, value: isSearchActive)
                            .zIndex(5)
                    }
                    .frame(maxHeight: .infinity)
                }

                // Tap-to-dismiss overlay when search is active
                if isSearchActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dismissSearch()
                            }
                        }
                        .zIndex(50)

                    searchBarOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .onChange(of: selectedTab) { _, _ in
                dismissSearch()
                showCategoryDropdown = false
                // Exit edit mode on all VMs
                taskListVM.exitEditMode()
                projectsVM.exitEditMode()
                listsVM.exitEditMode()
            }
            // Batch create project alert (Tasks tab)
            .alert("Create Project", isPresented: $showCreateProjectAlert) {
                TextField("Project title", text: $newProjectTitle)
                Button("Cancel", role: .cancel) { newProjectTitle = "" }
                Button("Create") {
                    let title = newProjectTitle
                    newProjectTitle = ""
                    _Concurrency.Task { @MainActor in
                        await taskListVM.createProjectFromSelected(title: title)
                    }
                }
            } message: {
                Text("Enter a name for the new project")
            }
            // Batch create list alert (Tasks tab)
            .alert("Create List", isPresented: $showCreateListAlert) {
                TextField("List title", text: $newListTitle)
                Button("Cancel", role: .cancel) { newListTitle = "" }
                Button("Create") {
                    let title = newListTitle
                    newListTitle = ""
                    _Concurrency.Task { @MainActor in
                        await taskListVM.createListFromSelected(title: title)
                    }
                }
            } message: {
                Text("Enter a name for the new list")
            }
        }
    }

    // MARK: - Search Pill Button

    private var searchPillButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isSearchActive = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }

    // MARK: - Search Bar Overlay (Above Keyboard)

    private var searchBarOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dismissSearch()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal)
    }

    private func dismissSearch() {
        searchText = ""
        isSearchActive = false
        isSearchFieldFocused = false
    }

    // MARK: - Shared Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        switch selectedTab {
        case 0:
            LogFilterBar(viewModel: taskListVM, showCategoryDropdown: $showCategoryDropdown)
        case 1:
            LogFilterBar(viewModel: listsVM, showCategoryDropdown: $showCategoryDropdown)
        case 2:
            LogFilterBar(viewModel: projectsVM, showCategoryDropdown: $showCategoryDropdown)
        default:
            EmptyView()
        }
    }

    // MARK: - Shared Category Dropdown

    @ViewBuilder
    private var categoryDropdown: some View {
        if showCategoryDropdown {
            switch selectedTab {
            case 0:
                SharedCategoryDropdownMenu(viewModel: taskListVM, showDropdown: $showCategoryDropdown)
            case 1:
                SharedCategoryDropdownMenu(viewModel: listsVM, showDropdown: $showCategoryDropdown)
            case 2:
                SharedCategoryDropdownMenu(viewModel: projectsVM, showDropdown: $showCategoryDropdown)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Shared Floating Bottom Area (FAB / Edit Action Bar)

    @ViewBuilder
    private var floatingBottomArea: some View {
        switch selectedTab {
        case 0:
            taskTabBottomArea
        case 1:
            listTabBottomArea
        case 2:
            projectTabBottomArea
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var taskTabBottomArea: some View {
        if taskListVM.isEditMode {
            EditModeActionBar(
                viewModel: taskListVM,
                showCreateProjectAlert: $showCreateProjectAlert,
                showCreateListAlert: $showCreateListAlert
            )
            .transition(.scale.combined(with: .opacity))
        } else {
            fabButton { taskListVM.showingAddItem = true }
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var projectTabBottomArea: some View {
        if projectsVM.isEditMode {
            EditModeActionBar(viewModel: projectsVM)
                .transition(.scale.combined(with: .opacity))
        } else {
            fabButton { projectsVM.showingAddItem = true }
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var listTabBottomArea: some View {
        if listsVM.isEditMode {
            EditModeActionBar(viewModel: listsVM)
                .transition(.scale.combined(with: .opacity))
        } else {
            fabButton { listsVM.showingAddItem = true }
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func fabButton(action: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    action()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    LogTabView()
}
