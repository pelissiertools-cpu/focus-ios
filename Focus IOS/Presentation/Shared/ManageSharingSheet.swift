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
            leadingButton: .close { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppStyle.Spacing.comfortable) {
                    // Members card
                    membersCard

                    // Actions card
                    actionsCard
                }
                .padding(.bottom, AppStyle.Spacing.page)
            }
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
    }

    // MARK: - Members Card

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(task.title)
                .font(.inter(.headline, weight: .semiBold))
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.compact)

            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
                .padding(.horizontal, AppStyle.Spacing.content)

            // Content
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, AppStyle.Spacing.expanded)
            } else if members.isEmpty {
                Text("No members yet")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.section)
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        memberRow(member)

                        if member.id != members.last?.id {
                            Rectangle()
                                .fill(Color.cardBorder)
                                .frame(height: AppStyle.Border.thin)
                                .padding(.leading, 52)
                                .padding(.trailing, AppStyle.Spacing.content)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: 0) {
            // Share Link
            Button {
                ShareSheetHelper.share(task: task)
            } label: {
                HStack(spacing: AppStyle.Spacing.medium) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.inter(.body))
                        .foregroundColor(.focusBlue)
                        .frame(width: AppStyle.Layout.pillButton)
                    Text("Share Link")
                        .font(.inter(.body))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.comfortable)
                .contentShape(Rectangle())
            }

            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
                .padding(.horizontal, AppStyle.Spacing.content)

            // Stop Sharing / Leave
            if isCurrentUserOwner {
                Button {
                    showStopSharingConfirmation = true
                } label: {
                    HStack(spacing: AppStyle.Spacing.medium) {
                        Image(systemName: "xmark.circle")
                            .font(.inter(.body))
                            .foregroundColor(.red)
                            .frame(width: AppStyle.Layout.pillButton)
                        Text("Stop Sharing")
                            .font(.inter(.body))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                    .contentShape(Rectangle())
                }
            } else {
                Button {
                    showLeaveConfirmation = true
                } label: {
                    HStack(spacing: AppStyle.Spacing.medium) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.body))
                            .foregroundColor(.red)
                            .frame(width: AppStyle.Layout.pillButton)
                        Text("Leave")
                            .font(.inter(.body))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Member Row

    private func memberRow(_ member: ShareMember) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            let initial = String(member.email.prefix(1)).uppercased()
            Text(initial)
                .font(.inter(.subheadline, weight: .semiBold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(member.isOwner ? Color.focusBlue : Color.secondary.opacity(0.6), in: Circle())

            VStack(alignment: .leading, spacing: AppStyle.Spacing.micro) {
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
                        .font(.inter(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.vertical, AppStyle.Spacing.compact)
    }

    // MARK: - Data

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
