//
//  QuickListsPage.swift
//  Focus IOS
//

import SwiftUI

struct QuickListsPage: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var listToDelete: FocusTask?
    @State private var selectedList: FocusTask?

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _listsViewModel = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Quick Lists")
                        .font(.inter(.title2, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    if viewModel.lists.isEmpty {
                        Text("No lists yet")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        ForEach(viewModel.lists) { list in
                            listRow(list)
                        }
                    }
                }
                .padding(.bottom, listsViewModel.isEditMode ? 100 : 20)
            }

            if listsViewModel.isEditMode {
                EditModeActionBar(viewModel: listsViewModel)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationDestination(item: $selectedList) { list in
            ListContentView(list: list, viewModel: listsViewModel)
        }
        .sheet(item: $listsViewModel.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsViewModel)
                .drawerStyle()
        }
        .sheet(item: $listsViewModel.selectedItemForSchedule) { item in
            ScheduleSelectionSheet(task: item, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $listsViewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: listsViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $listsViewModel.showBatchScheduleSheet) {
            BatchScheduleSheet(viewModel: listsViewModel)
                .drawerStyle()
        }
        .task {
            if viewModel.lists.isEmpty {
                await viewModel.fetchLists()
            }
            await listsViewModel.fetchLists()
        }
        .onChange(of: listsViewModel.selectedListForDetails) { _, newValue in
            if newValue == nil {
                _Concurrency.Task { await viewModel.fetchLists() }
            }
        }
        .alert("Delete List", isPresented: Binding(
            get: { listToDelete != nil },
            set: { if !$0 { listToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let list = listToDelete {
                    _Concurrency.Task { await viewModel.deleteList(list) }
                }
            }
            Button("Cancel", role: .cancel) { listToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(listToDelete?.title ?? "")\"?")
        }
        .alert("Delete Selected", isPresented: $listsViewModel.showBatchDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await listsViewModel.batchDeleteLists()
                    await viewModel.fetchLists()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(listsViewModel.selectedCount) list\(listsViewModel.selectedCount == 1 ? "" : "s")?")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if listsViewModel.isEditMode {
                        listsViewModel.exitEditMode()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: listsViewModel.isEditMode ? "xmark" : "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .contentShape(Circle())
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if listsViewModel.isEditMode {
                    Button {
                        if listsViewModel.allUncompletedSelected {
                            listsViewModel.deselectAll()
                        } else {
                            listsViewModel.selectAllUncompleted()
                        }
                    } label: {
                        Text(listsViewModel.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            listsViewModel.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
    }

    // MARK: - List Row

    @ViewBuilder
    private func listRow(_ list: FocusTask) -> some View {
        HStack(spacing: 12) {
            if listsViewModel.isEditMode {
                Image(systemName: listsViewModel.selectedListIds.contains(list.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(listsViewModel.selectedListIds.contains(list.id) ? .appRed : .secondary)
            }

            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if !listsViewModel.isEditMode {
                Image(systemName: "chevron.right")
                    .font(.inter(size: 12, weight: .semiBold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if listsViewModel.isEditMode {
                listsViewModel.toggleListSelection(list.id)
            } else {
                selectedList = list
            }
        }
        .contextMenu {
            if !listsViewModel.isEditMode {
                ContextMenuItems.editButton { listsViewModel.selectedListForDetails = list }
                ContextMenuItems.scheduleButton { listsViewModel.selectedItemForSchedule = list }
                Divider()
                ContextMenuItems.deleteButton { listToDelete = list }
            }
        }
    }
}
