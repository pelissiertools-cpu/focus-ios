//
//  LogFilterBar.swift
//  Focus IOS
//
//  Shared filter bar rendered by LogTabView across all tabs.
//

import SwiftUI

struct LogFilterBar<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @Binding var showCategoryDropdown: Bool
    @EnvironmentObject var languageManager: LanguageManager

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
                        Text(LocalizedStringKey(viewModel.allUncompletedSelected ? "Deselect All" : "Select All"))
                            .font(.sf(.subheadline, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    Text("\(viewModel.selectedCount) selected")
                        .font(.sf(.subheadline))
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
                    .padding(.leading, 20)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
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
                if viewModel.isEditMode {
                    Text("Done")
                        .font(.sf(.subheadline, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, viewModel.isEditMode ? 4 : 20)
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}
