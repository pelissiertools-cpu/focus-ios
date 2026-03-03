//
//  ArchiveView.swift
//  Focus IOS
//

import SwiftUI

struct ArchiveView: View {
    @StateObject private var viewModel = ArchiveViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Archive")
                    .font(.inter(size: 28, weight: .regular))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                // Count + Clear
                if viewModel.totalCount > 0 {
                    HStack(spacing: 0) {
                        Text("\(viewModel.totalCount) Completed")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)

                        Text("  ·  ")
                            .foregroundColor(.secondary)

                        Button {
                            viewModel.showClearConfirmation = true
                        } label: {
                            Text("Clear")
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(.completedPurple)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.sections.isEmpty {
                    VStack(spacing: 4) {
                        Text("No completed items")
                            .font(.inter(.headline))
                            .bold()
                        Text("Completed tasks, projects, and lists will appear here")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(viewModel.sections) { section in
                        ArchiveSectionHeader(title: section.title)

                        ForEach(section.tasks) { task in
                            ArchiveItemRow(
                                task: task,
                                isEditMode: viewModel.isEditMode,
                                isSelected: viewModel.selectedIds.contains(task.id),
                                onToggleSelection: { viewModel.toggleSelection(task.id) }
                            )
                            .padding(.horizontal, 32)
                        }
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.isEditMode {
                    Button {
                        viewModel.exitEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isEditMode {
                    Button {
                        if viewModel.allSelected {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
                        }
                    } label: {
                        Text(viewModel.allSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            viewModel.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isEditMode && !viewModel.selectedIds.isEmpty {
                Button {
                    viewModel.showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Delete \(viewModel.selectedIds.count)")
                    }
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.appRed, in: Capsule())
                    .shadow(radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
        }
        .alert("Delete \(viewModel.selectedIds.count) item\(viewModel.selectedIds.count == 1 ? "" : "s")?",
               isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteSelected()
                }
            }
        } message: {
            Text("This will permanently delete the selected items.")
        }
        .alert("Clear all completed items?",
               isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.clearAll()
                }
            }
        } message: {
            Text("This will permanently delete all \(viewModel.totalCount) completed items.")
        }
        .task {
            await viewModel.fetchCompletedItems()
        }
    }
}

// MARK: - Archive Section Header

private struct ArchiveSectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.inter(size: 22, weight: .semiBold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.secondary.opacity(0.7))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Archive Item Row

private struct ArchiveItemRow: View {
    let task: FocusTask
    let isEditMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.inter(.title3))
                    .foregroundColor(.completedPurple)
            }

            Text(task.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if task.type == .project {
                ProjectIconShape()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.secondary)
            } else if task.type == .list {
                Image(systemName: "list.bullet")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onToggleSelection()
            }
        }
    }
}
