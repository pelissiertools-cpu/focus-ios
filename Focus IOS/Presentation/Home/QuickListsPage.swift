//
//  QuickListsPage.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct QuickListsPage: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var coachMarkManager: CoachMarkManager
    @Environment(\.dismiss) private var dismiss
    @State private var listToDelete: FocusTask?
    @State private var selectedList: FocusTask?
    @State private var editingSectionId: UUID?
    @State private var scrollToSectionId: UUID?
    @State private var showingAddBar = false
    @State private var coachMarkVisible = false

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _listsViewModel = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
            List {
                HStack(spacing: AppStyle.Spacing.medium) {
                    Image(systemName: "checklist")
                        .font(.helveticaNeue(size: 15, weight: .medium))
                        .foregroundColor(.appText)
                        .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                        .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                    Text("Quick Lists")
                        .pageTitleStyle()
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.section, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                if viewModel.lists.isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No lists yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Your quick lists will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.comfortable, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                } else {
                    ForEach(viewModel.lists.filter { !$0.isCompleted && !$0.isCleared }) { item in
                        if item.isSection {
                            SectionDividerRow(
                                section: item,
                                editingSectionId: $editingSectionId,
                                onRename: { section, newTitle in
                                    await viewModel.renameSection(section, newTitle: newTitle)
                                },
                                onDelete: { section in
                                    await viewModel.deleteSection(section)
                                }
                            )
                            .id(item.id)
                            .listRowInsets(AppStyle.Insets.row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    _Concurrency.Task {
                                        await viewModel.deleteSection(item)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else {
                            listRow(item)
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.reorderLists(from: from, to: to)
                    }

                }

                Color.clear
                    .frame(height: listsViewModel.isEditMode ? 100 : 500)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            .onChange(of: scrollToSectionId) { _, newId in
                if let sectionId = newId {
                    scrollToSectionId = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(sectionId, anchor: UnitPoint(x: 0.5, y: 0.75))
                        }
                    }
                }
            }
            }

            // Coach mark
            if coachMarkVisible && coachMarkManager.shouldShow(.quickLists) {
                VStack {
                    Spacer()
                    CoachMarkCardView(section: .quickLists) {
                        withAnimation(AppStyle.Anim.expand) {
                            coachMarkManager.dismiss(.quickLists)
                        }
                    }
                    .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
                .allowsHitTesting(true)
            }

            if listsViewModel.isEditMode {
                EditModeActionBar(viewModel: listsViewModel)
                    .transition(.scale.combined(with: .opacity))
            }

            if !showingAddBar && !listsViewModel.isEditMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                showingAddBar = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.title2, weight: .semiBold))
                                .foregroundColor(.appText)
                                .frame(width: AppStyle.Layout.fab, height: AppStyle.Layout.fab)
                                .background(Color.cardBackground, in: Circle())
                                .overlay(Circle().stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin))
                                .fabShadow()
                        }
                        .accessibilityLabel("Add list")
                        .padding(.trailing, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.page)
                    }
                }
            }

            if showingAddBar {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(50)

                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = false
                            }
                        }

                    AddBar(
                        config: .quickLists,
                        categories: listsViewModel.categories,
                        activeMode: .constant(.list),
                        onSave: { result in
                            guard case .list(let r) = result else { return }
                            _Concurrency.Task { @MainActor in
                                await listsViewModel.createList(title: r.title, categoryId: r.categoryId, priority: r.priority)
                                if let createdList = listsViewModel.lists.first {
                                    for itemTitle in r.itemTitles {
                                        await listsViewModel.createItem(title: itemTitle, listId: createdList.id)
                                    }
                                    if !r.itemTitles.isEmpty {
                                        listsViewModel.expandedLists.insert(createdList.id)
                                    }
                                    if let sched = r.schedule {
                                        for date in sched.dates {
                                            let schedule = Schedule(
                                                userId: createdList.userId,
                                                taskId: createdList.id,
                                                timeframe: sched.timeframe,
                                                section: sched.section,
                                                scheduleDate: date,
                                                sortOrder: 0,
                                                scheduledTime: nil,
                                                durationMinutes: nil
                                            )
                                            _ = try? await listsViewModel.scheduleRepository.createSchedule(schedule)
                                        }
                                        await focusViewModel.fetchSchedules()
                                        await listsViewModel.fetchScheduledTaskIds()
                                    }
                                }
                                await viewModel.fetchLists()
                                await listsViewModel.fetchLists()
                            }
                        },
                        onDismiss: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = false
                            }
                        }
                    )
                    .padding(.bottom, AppStyle.Spacing.compact)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(51)
            }
        }
        .navigationDestination(item: $selectedList) { list in
            ListContentView(list: list, viewModel: listsViewModel)
        }
        .sheet(item: $listsViewModel.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsViewModel, onGoToList: {
                selectedList = list
            })
                .drawerStyle()
        }
        .sheet(item: $listsViewModel.selectedItemForSchedule) { item in
            ScheduleSelectionSheet(
                task: item,
                focusViewModel: focusViewModel
            )
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
        .onAppear {
            if coachMarkManager.shouldShow(.quickLists) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(AppStyle.Anim.expand) {
                        coachMarkVisible = true
                    }
                }
            }
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
                        .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(listsViewModel.isEditMode ? "Cancel" : "Back")
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
                            .foregroundColor(.focusBlue)
                    }
                } else {
                    Menu {
                        Button {
                            listsViewModel.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }

                        Button {
                            _Concurrency.Task {
                                guard let userId = authService.currentUser?.id else { return }
                                if let section = await viewModel.createSection(type: .list, userId: userId) {
                                    editingSectionId = section.id
                                    scrollToSectionId = section.id
                                }
                            }
                        } label: {
                            Label("Add section", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
    }

    // MARK: - List Row

    @ViewBuilder
    private func listRow(_ list: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if listsViewModel.isEditMode {
                Image(systemName: listsViewModel.selectedListIds.contains(list.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(listsViewModel.selectedListIds.contains(list.id) ? .appRed : .secondary)
            }

            Circle()
                .fill(Color.todayBadge)
                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            if list.isPinned {
                Image(systemName: "pin.fill")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary)
            }

            if listsViewModel.sharedTaskIds.contains(list.id) {
                Image(systemName: "person.2.fill")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary)
            }

            Spacer()

        }
        .padding(.vertical, AppStyle.Spacing.medium)
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
                ContextMenuItems.pinButton(isPinned: list.isPinned) {
                    _Concurrency.Task { await viewModel.togglePin(list) }
                }
                ContextMenuItems.shareButton { ShareSheetHelper.share(task: list) }
                Divider()
                ContextMenuItems.deleteButton { listToDelete = list }
            }
        }
    }
}
