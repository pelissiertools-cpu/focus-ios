//
//  ManageSharingSheet.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct ManageSharingSheet: View {
    let task: FocusTask
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var members: [ShareMember] = []
    @State private var isLoading = true
    @State private var showStopSharingConfirmation = false
    @State private var showLeaveConfirmation = false

    private let shareRepository = ShareRepository()

    private var isCurrentUserOwner: Bool {
        task.userId == authService.currentUser?.id
    }

    var body: some View {
        DrawerContainer(
            title: "Sharing",
            leadingButton: .done { dismiss() }
        ) {
            contentList
        }
    }

    private var contentList: some View {
        List {
            // Members
            SwiftUI.Section(header: Text(task.title)
                .font(.inter(.headline, weight: .semiBold))
                .foregroundColor(.primary)
                .textCase(nil)
            ) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if members.isEmpty {
                    Text("No members yet")
                        .font(.inter(.body))
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
            }

            // Actions
            SwiftUI.Section {
                Button {
                    ShareSheetHelper.share(task: task)
                } label: {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                }
                .listRowBackground(Color.clear)

                if isCurrentUserOwner {
                    Button(role: .destructive) {
                        showStopSharingConfirmation = true
                    } label: {
                        Label("Stop Sharing", systemImage: "xmark.circle")
                            .font(.inter(.body))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Button(role: .destructive) {
                        showLeaveConfirmation = true
                    } label: {
                        Label("Leave", systemImage: "arrow.right.circle")
                            .font(.inter(.body))
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .task {
            await loadMembers()
        }
        .confirmationDialog("Stop sharing?", isPresented: $showStopSharingConfirmation, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) {
                _Concurrency.Task {
                    try? await shareRepository.removeShare(taskId: task.id)
                    NotificationCenter.default.post(name: .sharedItemsChanged, object: nil)
                    NotificationCenter.default.post(name: .projectListChanged, object: nil)
                    dismiss()
                }
            }
        } message: {
            Text("All members will lose access to \"\(task.title)\".")
        }
        .confirmationDialog("Leave shared item?", isPresented: $showLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                _Concurrency.Task {
                    if let userId = authService.currentUser?.id {
                        try? await shareRepository.leaveShare(taskId: task.id, userId: userId)
                        NotificationCenter.default.post(name: .sharedItemsChanged, object: nil)
                        NotificationCenter.default.post(name: .projectListChanged, object: nil)
                    }
                    dismiss()
                }
            }
        } message: {
            Text("\"\(task.title)\" will be removed from your lists.")
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ShareMember) -> some View {
        HStack(spacing: 12) {
            let initial = String(member.email.prefix(1)).uppercased()
            Text(initial)
                .font(.inter(.subheadline, weight: .semiBold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(member.isOwner ? Color.accentColor : Color.secondary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(member.email)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(member.isOwner ? "Owner" : "Member")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isCurrentUserOwner && !member.isOwner {
                Button {
                    _Concurrency.Task {
                        try? await shareRepository.removeMember(taskId: task.id, userId: member.userId)
                        await loadMembers()
                        NotificationCenter.default.post(name: .sharedItemsChanged, object: nil)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
    }

    private func loadMembers() async {
        isLoading = true
        do {
            members = try await shareRepository.fetchMembers(taskId: task.id)
        } catch {
            print("[ManageSharingSheet] Failed to load members: \(error)")
        }
        isLoading = false
    }
}
