//
//  EditModeActionBar.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct EditModeActionBar: View {
    @ObservedObject var viewModel: TaskListViewModel
    @Binding var showBatchMovePicker: Bool
    @Binding var showBatchCommitSheet: Bool
    @Binding var showCreateProjectAlert: Bool
    @Binding var showCreateListAlert: Bool
    @Binding var showBatchDeleteConfirmation: Bool

    private var hasSelection: Bool { !viewModel.selectedTaskIds.isEmpty }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isDestructive: Bool
        let action: () -> Void
    }

    private var actions: [ActionItem] {
        [
            ActionItem(icon: "trash", label: "Delete", isDestructive: true) {
                showBatchDeleteConfirmation = true
            },
            ActionItem(icon: "arrow.right", label: "Move", isDestructive: false) {
                showBatchMovePicker = true
            },
            ActionItem(icon: "calendar", label: "Commit", isDestructive: false) {
                showBatchCommitSheet = true
            },
            ActionItem(icon: "folder.badge.plus", label: "Project", isDestructive: false) {
                showCreateProjectAlert = true
            },
            ActionItem(icon: "list.bullet", label: "List", isDestructive: false) {
                showCreateListAlert = true
            },
        ]
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // Floating labels + vertical icon capsule
                HStack(alignment: .bottom, spacing: 14) {
                    // Floating labels column (each tappable)
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { _, item in
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                                .frame(height: 52)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasSelection { item.action() }
                                }
                        }
                    }

                    // Vertical glass capsule with icons (~20% larger)
                    VStack(spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { index, item in
                            Button {
                                item.action()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasSelection)

                            if index < actions.count - 1 {
                                Divider()
                                    .frame(width: 28)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(radius: 4, y: 2)
                }
                .opacity(hasSelection ? 1.0 : 0.5)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            // Block all taps from passing through to task list
            .contentShape(Rectangle())
        }
    }
}
