//
//  LibraryTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct LibraryTabView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchFocused: Bool = false

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
            VStack(spacing: 0) {
                // Search bar
                HStack {
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                .padding(.horizontal)
                .padding(.top, 8)

                // Picker for Tasks/Projects/Lists
                Picker("Library Type", selection: $selectedTab) {
                    Text("Tasks").tag(0)
                    Text("Projects").tag(1)
                    Text("Lists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content with shared controls overlay
                ZStack(alignment: .topLeading) {
                    // Tab content
                    Group {
                        switch selectedTab {
                        case 0:
                            TasksListView(viewModel: taskListVM, searchText: searchText, isSearchFocused: $isSearchFocused)
                        case 1:
                            ProjectsListView(viewModel: projectsVM, searchText: searchText)
                        case 2:
                            ListsView(viewModel: listsVM, searchText: searchText)
                        default:
                            TasksListView(viewModel: taskListVM, searchText: searchText)
                        }
                    }

                    // Shared filter bar (floats on top)
                    filterBar
                        .zIndex(10)

                    // Shared category dropdown overlay
                    categoryDropdown
                        .zIndex(20)

                    // Shared floating bottom area (FAB or EditModeActionBar)
                    if !isSearchFocused {
                        floatingBottomArea
                            .zIndex(5)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .onChange(of: selectedTab) { _, _ in
                searchText = ""
                isSearchFieldFocused = false
                isSearchFocused = false
                showCategoryDropdown = false
                // Exit edit mode on all VMs
                taskListVM.exitEditMode()
                projectsVM.exitEditMode()
                listsVM.exitEditMode()
            }
            .onChange(of: isSearchFieldFocused) { _, newValue in
                isSearchFocused = newValue
            }
            .onChange(of: isSearchFocused) { _, newValue in
                isSearchFieldFocused = newValue
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

    // MARK: - Shared Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        switch selectedTab {
        case 0:
            LibraryFilterBar(viewModel: taskListVM, showCategoryDropdown: $showCategoryDropdown)
        case 1:
            LibraryFilterBar(viewModel: projectsVM, showCategoryDropdown: $showCategoryDropdown)
        case 2:
            LibraryFilterBar(viewModel: listsVM, showCategoryDropdown: $showCategoryDropdown)
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
                SharedCategoryDropdownMenu(viewModel: projectsVM, showDropdown: $showCategoryDropdown)
            case 2:
                SharedCategoryDropdownMenu(viewModel: listsVM, showDropdown: $showCategoryDropdown)
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
            projectTabBottomArea
        case 2:
            listTabBottomArea
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
        if !listsVM.isEditMode {
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
    LibraryTabView()
}
