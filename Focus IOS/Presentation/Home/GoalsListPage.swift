//
//  GoalsListPage.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct GoalsListPage: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var goalsViewModel: GoalsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var goalToDelete: FocusTask?
    @State private var selectedGoal: FocusTask?
    @State private var editingSectionId: UUID?
    @State private var showingCreateGoal = false

    private let authService: AuthService

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _goalsViewModel = StateObject(wrappedValue: GoalsViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            List {
                Text("Goals")
                    .pageTitleStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.section, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                if goalsViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: AppStyle.Spacing.page, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                } else if goalsViewModel.filteredGoals.isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No goals yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("Tap + to create your first goal")
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
                    ForEach(goalsViewModel.filteredGoals) { item in
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
                            goalRow(item)
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { from, to in
                        viewModel.reorderGoals(from: from, to: to)
                    }

                }

                Color.clear
                    .frame(height: goalsViewModel.isEditMode ? 100 : AppStyle.Spacing.page)
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

            if goalsViewModel.isEditMode {
                EditModeActionBar(viewModel: goalsViewModel)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationDestination(item: $selectedGoal) { goal in
            GoalContentView(goal: goal, viewModel: goalsViewModel)
        }
        .sheet(item: $goalsViewModel.selectedGoalForDetails) { goal in
            GoalDetailsDrawer(goal: goal, viewModel: goalsViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalDrawer(viewModel: goalsViewModel)
                .drawerStyle()
        }
        .sheet(item: $goalsViewModel.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
        .sheet(isPresented: $goalsViewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: goalsViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $goalsViewModel.showBatchScheduleSheet) {
            BatchScheduleSheet(viewModel: goalsViewModel)
                .drawerStyle()
        }
        .task {
            await goalsViewModel.fetchGoals()
        }
        .onChange(of: goalsViewModel.selectedGoalForDetails) { _, newValue in
            if newValue == nil {
                _Concurrency.Task { await viewModel.fetchGoals() }
            }
        }
        .onChange(of: showingCreateGoal) { _, newValue in
            if !newValue {
                _Concurrency.Task { await viewModel.fetchGoals() }
            }
        }
        .alert("Delete Goal", isPresented: Binding(
            get: { goalToDelete != nil },
            set: { if !$0 { goalToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let goal = goalToDelete {
                    _Concurrency.Task { await viewModel.deleteGoal(goal) }
                }
            }
            Button("Cancel", role: .cancel) { goalToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(goalToDelete?.title ?? "")\"?")
        }
        .alert("Delete Selected", isPresented: $goalsViewModel.showBatchDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await goalsViewModel.batchDeleteGoals()
                    await viewModel.fetchGoals()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(goalsViewModel.selectedCount) goal\(goalsViewModel.selectedCount == 1 ? "" : "s")?")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if goalsViewModel.isEditMode {
                        goalsViewModel.exitEditMode()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: goalsViewModel.isEditMode ? "xmark" : "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(goalsViewModel.isEditMode ? "Cancel" : "Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if goalsViewModel.isEditMode {
                    Button {
                        if goalsViewModel.allUncompletedSelected {
                            goalsViewModel.deselectAll()
                        } else {
                            goalsViewModel.selectAllUncompleted()
                        }
                    } label: {
                        Text(goalsViewModel.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Button {
                            showingCreateGoal = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.body, weight: .semiBold))
                                .foregroundColor(.primary)
                                .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                                .background(Color.pillBackground, in: Circle())
                        }
                        .accessibilityLabel("Add goal")

                        Menu {
                            Button {
                                goalsViewModel.enterEditMode()
                            } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }

                            Button {
                                _Concurrency.Task {
                                    guard let userId = authService.currentUser?.id else { return }
                                    if let section = await viewModel.createSection(type: .goal, userId: userId) {
                                        editingSectionId = section.id
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
                        .accessibilityLabel("More options")
                    }
                }
            }
        }
    }

    // MARK: - Goal Row

    @ViewBuilder
    private func goalRow(_ goal: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if goalsViewModel.isEditMode {
                Image(systemName: goalsViewModel.selectedGoalIds.contains(goal.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(goalsViewModel.selectedGoalIds.contains(goal.id) ? .appRed : .secondary)
            }

            Image("TargetIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: AppStyle.Layout.smallIcon, height: AppStyle.Layout.smallIcon)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.micro) {
                Text(goal.title)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let dueDate = goal.dueDate {
                    Text(dueDate, style: .date)
                        .font(.inter(.caption))
                        .foregroundColor(dueDate < Date() ? .red : .secondary)
                }
            }

            Spacer()

        }
        .padding(.vertical, AppStyle.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture {
            if goalsViewModel.isEditMode {
                goalsViewModel.toggleGoalSelection(goal.id)
            } else {
                selectedGoal = goal
            }
        }
        .contextMenu {
            if !goalsViewModel.isEditMode {
                ContextMenuItems.editButton { goalsViewModel.selectedGoalForDetails = goal }
                ContextMenuItems.scheduleButton { goalsViewModel.selectedTaskForSchedule = goal }
                ContextMenuItems.pinButton(isPinned: goal.isPinned) {
                    _Concurrency.Task { await viewModel.togglePin(goal) }
                }
                Divider()
                ContextMenuItems.deleteButton { goalToDelete = goal }
            }
        }
    }
}
