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
