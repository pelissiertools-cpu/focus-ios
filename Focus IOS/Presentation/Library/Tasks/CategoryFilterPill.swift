//
//  CategoryFilterPill.swift
//  Focus IOS
//

import SwiftUI

struct CategoryFilterPill: View {
    @ObservedObject var viewModel: TaskListViewModel
    @State private var showDropdown = false
    @State private var newCategoryName = ""
    @State private var isAddingCategory = false
    @FocusState private var isTextFieldFocused: Bool

    private var selectedCategoryName: String {
        if let id = viewModel.selectedCategoryId,
           let category = viewModel.categories.first(where: { $0.id == id }) {
            return category.name
        }
        return "All"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss layer when expanded
            if showDropdown {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { closeDropdown() }
                    .zIndex(5)
            }

            // Unified expandable container
            VStack(alignment: .leading, spacing: 0) {
                // Header row (always visible)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDropdown.toggle()
                    }
                    if !showDropdown {
                        isAddingCategory = false
                        newCategoryName = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedCategoryName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Image(systemName: showDropdown ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(viewModel.selectedCategoryId != nil ? .white : .secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                // Expanded content
                if showDropdown {
                    Divider()
                        .padding(.horizontal, 8)

                    // "All" option
                    Button {
                        viewModel.selectCategory(nil)
                        closeDropdown()
                    } label: {
                        HStack {
                            Text("All")
                                .font(.body)
                            Spacer()
                            if viewModel.selectedCategoryId == nil {
                                Image(systemName: "checkmark")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Category list
                    ForEach(viewModel.categories) { category in
                        Button {
                            viewModel.selectCategory(category.id)
                            closeDropdown()
                        } label: {
                            HStack {
                                Text(category.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer()
                                if viewModel.selectedCategoryId == category.id {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .padding(.horizontal, 8)

                    // Add new category
                    if isAddingCategory {
                        HStack(spacing: 8) {
                            TextField("Category name", text: $newCategoryName)
                                .font(.body)
                                .focused($isTextFieldFocused)
                                .onSubmit { submitNewCategory() }
                            Button {
                                submitNewCategory()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(
                                        newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? .gray : .blue
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    } else {
                        Button {
                            isAddingCategory = true
                            isTextFieldFocused = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                Text("New Category")
                                    .font(.body)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(showDropdown
                          ? Color(.systemBackground)
                          : (viewModel.selectedCategoryId != nil
                             ? Color.blue
                             : Color.secondary.opacity(0.15)))
                    .shadow(color: showDropdown ? .black.opacity(0.15) : .clear,
                            radius: 8, x: 0, y: 4)
            )
            .fixedSize(horizontal: true, vertical: true)
            .zIndex(10)
        }
    }

    // MARK: - Helpers

    private func closeDropdown() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showDropdown = false
        }
        isAddingCategory = false
        newCategoryName = ""
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            await viewModel.createCategory(name: name)
        }
        closeDropdown()
    }
}
