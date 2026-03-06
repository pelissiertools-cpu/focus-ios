import SwiftUI

/// Shared context menu building blocks for unified long-press menus across the app.
enum ContextMenuItems {

    // MARK: - Edit

    @ViewBuilder
    static func editButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
    }

    // MARK: - Assign

    @ViewBuilder
    static func assignButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Assign", systemImage: "calendar.badge.plus")
        }
    }

    // MARK: - Category Submenu

    @ViewBuilder
    static func categorySubmenu(
        currentCategoryId: UUID?,
        categories: [Category],
        onMove: @escaping (UUID?) -> Void
    ) -> some View {
        Menu {
            Button {
                onMove(nil)
            } label: {
                if currentCategoryId == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }
            ForEach(categories) { category in
                Button {
                    onMove(category.id)
                } label: {
                    if currentCategoryId == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
        } label: {
            Label("Category", systemImage: "folder")
        }
    }

    // MARK: - Priority Submenu

    @ViewBuilder
    static func prioritySubmenu(
        currentPriority: Priority,
        onSelect: @escaping (Priority) -> Void
    ) -> some View {
        Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    onSelect(priority)
                } label: {
                    if currentPriority == priority {
                        Label(priority.displayName, systemImage: "checkmark")
                    } else {
                        Text(priority.displayName)
                    }
                }
            }
        } label: {
            Label("Priority", systemImage: "flag")
        }
    }

    // MARK: - Schedule

    @ViewBuilder
    static func scheduleButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Schedule", systemImage: "calendar")
        }
    }

    // MARK: - Reschedule

    @ViewBuilder
    static func rescheduleButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Reschedule", systemImage: "calendar.badge.clock")
        }
    }

    // MARK: - Push to Tomorrow

    @ViewBuilder
    static func pushToTomorrowButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Push to Tomorrow", systemImage: "arrow.right")
        }
    }

    // MARK: - Unschedule

    @ViewBuilder
    static func unscheduleButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label("Unschedule", systemImage: "calendar.badge.minus")
        }
    }

    // MARK: - Pin / Unpin

    @ViewBuilder
    static func pinButton(isPinned: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(isPinned ? "Unpin from Home" : "Pin to Home", systemImage: isPinned ? "pin.slash" : "pin")
        }
    }

    // MARK: - Delete

    @ViewBuilder
    static func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive) {
            action()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
