//
//  SharedFilterComponents.swift
//  Focus IOS
//
//  Generic filter components shared across all Log tabs.
//

import SwiftUI

// MARK: - Shared Category Filter Pill

struct SharedCategoryFilterPill<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @Binding var showDropdown: Bool

    private var selectedCategoryName: String {
        if let id = viewModel.selectedCategoryId,
           let category = viewModel.categories.first(where: { $0.id == id }) {
            return category.name
        }
        return "All"
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showDropdown.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedCategoryName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: showDropdown ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(viewModel.selectedCategoryId != nil ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                viewModel.selectedCategoryId != nil
                    ? Color.blue
                    : Color(.systemGray5),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Category Dropdown Menu

struct SharedCategoryDropdownMenu<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @Binding var showDropdown: Bool
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
            // Dismiss layer
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { closeDropdown() }

            // Floating dropdown menu
            VStack(alignment: .leading, spacing: 0) {
                // Header row (mirrors the pill appearance)
                HStack(spacing: 6) {
                    Text(selectedCategoryName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { closeDropdown() }

                Divider()
                    .padding(.horizontal, 16)

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
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
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
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.horizontal, 16)

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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                } else {
                    Button {
                        isAddingCategory = true
                        isTextFieldFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.body)
                            Text("New Category")
                                .font(.body)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
            }
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 200)
            .padding(.leading, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func closeDropdown() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDropdown = false
        }
        isAddingCategory = false
        newCategoryName = ""
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.createCategory(name: name)
        }
        closeDropdown()
    }
}

// MARK: - Shared Commitment Filter Pills

struct SharedCommitmentFilterPills<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM

    var body: some View {
        HStack(spacing: 8) {
            pillButton(label: "Committed", filter: .committed)
            pillButton(label: "Uncommitted", filter: .uncommitted)
        }
    }

    private func pillButton(label: String, filter: CommitmentFilter) -> some View {
        let isActive = viewModel.commitmentFilter == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleCommitmentFilter(filter)
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundColor(isActive ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    isActive ? Color.blue : Color(.systemGray5),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
