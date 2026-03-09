//
//  EditModeActionBar.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct EditModeActionBar<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @EnvironmentObject var languageManager: LanguageManager
    var showCreateProjectAlert: Binding<Bool>?
    var showCreateListAlert: Binding<Bool>?

    private var hasSelection: Bool { !viewModel.selectedItemIds.isEmpty }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isDestructive: Bool
        let action: () -> Void
    }

    private var actions: [ActionItem] {
        var items: [ActionItem] = [
            ActionItem(icon: "trash", label: "Delete", isDestructive: true) {
                viewModel.showBatchDeleteConfirmation = true
            },
            ActionItem(icon: "arrow.right", label: "Move", isDestructive: false) {
                viewModel.showBatchMovePicker = true
            },
            ActionItem(icon: "calendar", label: "Schedule", isDestructive: false) {
                viewModel.showBatchScheduleSheet = true
            },
        ]

        if let projectBinding = showCreateProjectAlert {
            items.append(ActionItem(icon: "folder.badge.plus", label: "Project", isDestructive: false) {
                projectBinding.wrappedValue = true
            })
        }

        if let listBinding = showCreateListAlert {
            items.append(ActionItem(icon: "checklist", label: "List", isDestructive: false) {
                listBinding.wrappedValue = true
            })
        }

        return items
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()

                // Floating labels + vertical icon capsule
                HStack(alignment: .top, spacing: AppStyle.Spacing.content) {
                    // Floating labels column (each tappable)
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { _, item in
                            Text(LocalizedStringKey(item.label))
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                                .frame(height: AppStyle.Layout.largeButton)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasSelection { item.action() }
                                }
                        }
                    }

                    // Vertical glass capsule with icons
                    VStack(spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { index, item in
                            Button {
                                item.action()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.inter(.title3))
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                    .frame(width: AppStyle.Layout.largeButton, height: AppStyle.Layout.largeButton)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasSelection)
                            .accessibilityLabel(item.label)

                            if index < actions.count - 1 {
                                Divider()
                                    .frame(width: 28)
                            }
                        }
                    }
                    .padding(.vertical, AppStyle.Spacing.small)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(radius: 4, y: 2)
                }
                .opacity(hasSelection ? 1.0 : 0.5)
                .padding(.trailing, AppStyle.Spacing.page)
                .padding(.top, 62)
            }
            Spacer()
        }
    }
}
