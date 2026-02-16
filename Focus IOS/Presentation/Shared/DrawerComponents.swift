//
//  DrawerComponents.swift
//  Focus IOS
//
//  Shared components for unified drawer/sheet UI across the app.
//

import SwiftUI

// MARK: - Drawer Button

enum DrawerButton {
    case done(action: () -> Void)
    case cancel(action: () -> Void)
    case save(action: () -> Void, disabled: Bool = false)
    case add(action: () -> Void, disabled: Bool = false)
    case close(action: () -> Void)
    case check(action: () -> Void, highlighted: Bool = false)
}

// MARK: - Drawer Container

struct DrawerContainer<Content: View>: View {
    let title: String
    let leadingButton: DrawerButton
    var trailingButton: DrawerButton? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationView {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        leadingButtonView
                    }
                    if let trailingButton {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            trailingButtonView(trailingButton)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var leadingButtonView: some View {
        drawerButtonView(leadingButton)
    }

    @ViewBuilder
    private func trailingButtonView(_ button: DrawerButton) -> some View {
        drawerButtonView(button)
    }

    @ViewBuilder
    private func drawerButtonView(_ button: DrawerButton) -> some View {
        switch button {
        case .done(let action):
            Button("Done", action: action)
        case .cancel(let action):
            Button("Cancel", action: action)
        case .save(let action, let disabled):
            Button("Save", action: action)
                .fontWeight(.semibold)
                .disabled(disabled)
        case .add(let action, let disabled):
            Button("Add", action: action)
                .fontWeight(.semibold)
                .disabled(disabled)
        case .close(let action):
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
            }
        case .check(let action, let highlighted):
            Button(action: action) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(highlighted ? .white : .secondary)
                    .frame(width: 30, height: 30)
            }
            .background(highlighted ? Color.accentColor : Color(.systemGray5))
            .clipShape(Circle())
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Drawer Title Section

struct DrawerTitleSection: View {
    let placeholder: String
    @Binding var title: String
    var autoFocus: Bool = false
    var onSubmit: (() -> Void)? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        SwiftUI.Section("Title") {
            TextField(placeholder, text: $title)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
                .onAppear {
                    if autoFocus {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
                }
        }
    }
}

// MARK: - Drawer Stats Row

struct DrawerStatsRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .foregroundColor(.secondary)
    }
}

// MARK: - Drawer Category Menu

struct DrawerCategoryMenu: View {
    let currentCategoryId: UUID?
    let categories: [Category]
    var onSelect: (UUID?) -> Void
    var onCreateNew: () -> Void

    private var currentCategoryName: String {
        if let id = currentCategoryId,
           let cat = categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "None"
    }

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                if currentCategoryId == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }

            ForEach(categories) { category in
                Button {
                    onSelect(category.id)
                } label: {
                    if currentCategoryId == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }

            Divider()

            Button {
                onCreateNew()
            } label: {
                Label("New Category", systemImage: "plus")
            }
        } label: {
            DrawerActionLabel(icon: "folder", text: "Category", trailing: currentCategoryName)
        }
    }
}

// MARK: - Drawer Delete Section

struct DrawerDeleteSection: View {
    let title: String
    var requiresConfirmation: Bool = false
    var confirmationTitle: String = ""
    var confirmationMessage: String = ""
    let onDelete: () -> Void

    @State private var showConfirmation = false

    var body: some View {
        SwiftUI.Section {
            Button(role: .destructive) {
                if requiresConfirmation {
                    showConfirmation = true
                } else {
                    onDelete()
                }
            } label: {
                Label(title, systemImage: "trash")
            }
        }
        .alert(confirmationTitle, isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text(confirmationMessage)
        }
    }
}

// MARK: - Compact Action Row (Button)

struct DrawerActionRow: View {
    let icon: String
    let text: String
    var trailing: String? = nil
    var iconColor: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DrawerActionLabel(icon: icon, text: text, trailing: trailing, iconColor: iconColor)
        }
    }
}

// MARK: - Compact Action Row (Menu)

struct DrawerActionMenuRow: View {
    let icon: String
    let text: String
    var trailing: String? = nil
    var iconColor: Color = .accentColor
    @ViewBuilder let menuContent: () -> AnyView

    var body: some View {
        Menu {
            menuContent()
        } label: {
            DrawerActionLabel(icon: icon, text: text, trailing: trailing, iconColor: iconColor)
        }
    }
}

// MARK: - Shared Action Label

struct DrawerActionLabel: View {
    let icon: String
    let text: String
    var trailing: String? = nil
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
