//
//  CommitmentFilterPills.swift
//  Focus IOS
//

import SwiftUI

struct CommitmentFilterPills: View {
    @ObservedObject var viewModel: TaskListViewModel

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
                .foregroundColor(isActive ? .white : .secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isActive ? Color.blue : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}
