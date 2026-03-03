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
                Text("Archive")
                    .font(.inter(size: 28, weight: .regular))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

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
                            ArchiveItemRow(task: task)
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
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                }
            }
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.inter(.title3))
                .foregroundColor(.completedPurple)

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
    }
}
