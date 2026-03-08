//
//  AddListBar.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct AddListBar: View {
    @ObservedObject var listsViewModel: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    var initialCategoryId: UUID? = nil
    var onSaved: (() -> Void)?
    var onDismiss: () -> Void

    // State
    @State private var title = ""
    @State private var items: [DraftSubtaskEntry] = []
    @State private var categoryId: UUID?
    @State private var priority: Priority = .low
    @State private var scheduleDates: Set<Date> = []
    @State private var scheduleDatesSnapshot: Set<Date> = []
    @State private var timeframe: Timeframe = .daily
    @State private var section: Section = .todo
    @State private var scheduleExpanded = false
    @State private var optionsExpanded = false

    @FocusState private var titleFocused: Bool
    @FocusState private var focusedItemId: UUID?

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var categoryPillLabel: String {
        if let categoryId,
           let category = listsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Create a new list", text: $title)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .submitLabel(.return)
                .onSubmit { save() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            DraftSubtaskListEditor(
                subtasks: $items,
                focusedSubtaskId: $focusedItemId,
                onAddNew: { addNewItem() },
                placeholder: "Item"
            )

            // Schedule expansion
            if scheduleExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
                    Picker("Section", selection: $section) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $scheduleDates,
                        selectedTimeframe: $timeframe
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleDates.removeAll()
                            scheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .accessibilityLabel("Clear schedule")
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = scheduleDates != scheduleDatesSnapshot
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Confirm schedule")
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 1: [Item] [...] Spacer [Checkmark]
            if !scheduleExpanded {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Button {
                        addNewItem()
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "plus")
                                .font(.inter(.caption))
                            Text("Item")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            optionsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.caption, weight: .bold))
                            .foregroundColor(.black)
                            .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                            .padding(.horizontal, AppStyle.Spacing.medium)
                            .padding(.vertical, AppStyle.Spacing.compact)
                            .background(Color.white, in: Capsule())
                    }
                    .accessibilityLabel("More options")
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(isTitleEmpty ? .secondary : .white)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                isTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Save list")
                    .buttonStyle(.plain)
                    .disabled(isTitleEmpty)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if optionsExpanded && !scheduleExpanded {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Menu {
                        Button {
                            categoryId = nil
                        } label: {
                            if categoryId == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }
                        ForEach(listsViewModel.categories) { category in
                            Button {
                                categoryId = category.id
                            } label: {
                                if self.categoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "folder")
                                .font(.inter(.caption))
                            Text(LocalizedStringKey(categoryPillLabel))
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                    }

                    Button {
                        scheduleDatesSnapshot = scheduleDates
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "arrow.right.circle")
                                .font(.inter(.caption))
                            Text("Schedule")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(!scheduleDates.isEmpty ? .white : .black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(!scheduleDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Button {
                                priority = p
                            } label: {
                                if priority == p {
                                    Label(p.displayName, systemImage: "checkmark")
                                } else {
                                    Text(p.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Circle()
                                .fill(priority.dotColor)
                                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                            Text(priority.displayName)
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
            }

            Spacer().frame(height: AppStyle.Spacing.page)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .onAppear {
            if let initialCategoryId {
                categoryId = initialCategoryId
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
        }
    }

    // MARK: - Helpers

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let itemTitles = items
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let catId = categoryId
        let pri = priority
        let scheduleEnabled = !scheduleDates.isEmpty
        let tf = timeframe
        let sec = section
        let dates = scheduleDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        titleFocused = true
        focusedItemId = nil

        title = ""
        items = []
        scheduleDates = []
        scheduleExpanded = false
        optionsExpanded = false
        priority = .low

        _Concurrency.Task { @MainActor in
            await listsViewModel.createList(title: trimmedTitle, categoryId: catId, priority: pri)

            if let createdList = listsViewModel.lists.first {
                for itemTitle in itemTitles {
                    await listsViewModel.createItem(title: itemTitle, listId: createdList.id)
                }
                if !itemTitles.isEmpty {
                    listsViewModel.expandedLists.insert(createdList.id)
                }

                if scheduleEnabled && !dates.isEmpty {
                    for date in dates {
                        let schedule = Schedule(
                            userId: createdList.userId,
                            taskId: createdList.id,
                            timeframe: tf,
                            section: sec,
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

            onSaved?()
        }
    }

    private func addNewItem() {
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            items.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedItemId = newEntry.id
        }
    }
}
