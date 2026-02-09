//
//  LibraryFilterBar.swift
//  Focus IOS
//
//  Shared filter bar rendered by LibraryTabView across all tabs.
//

import SwiftUI

struct LibraryFilterBar<VM: LibraryFilterable>: View {
    @ObservedObject var viewModel: VM
    @Binding var showCategoryDropdown: Bool

    var body: some View {
        HStack(spacing: 0) {
            if viewModel.isEditMode {
                // Edit mode: Select All + count
                HStack(spacing: 12) {
                    Button {
                        if viewModel.allUncompletedSelected {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAllUncompleted()
                        }
                    } label: {
                        Text(viewModel.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    Text("\(viewModel.selectedCount) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.leading)
            } else {
                // Normal mode: filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SharedCategoryFilterPill(viewModel: viewModel, showDropdown: $showCategoryDropdown)
                        SharedCommitmentFilterPills(viewModel: viewModel)
                    }
                    .padding(.leading)
                }
            }

            Spacer()

            // Edit / Done button
            Button {
                if viewModel.isEditMode {
                    viewModel.exitEditMode()
                } else {
                    viewModel.enterEditMode()
                }
            } label: {
                Text(viewModel.isEditMode ? "Done" : "Edit")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.top, 4)
    }
}
