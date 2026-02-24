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
