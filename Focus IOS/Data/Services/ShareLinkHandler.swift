//
//  ShareLinkHandler.swift
//  Focus IOS
//

import Foundation
import Combine

@MainActor
final class ShareLinkHandler: ObservableObject {
    static let shared = ShareLinkHandler()

    @Published var pendingToken: String?
    @Published var acceptedTaskName: String?
    @Published var showAcceptedAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    private let shareRepository = ShareRepository()
    private let taskRepository = TaskRepository()

    private init() {}

    /// Process a pending share token. Call after confirming user is authenticated.
    func processPendingShare() {
        guard let token = pendingToken else { return }
        pendingToken = nil

        _Concurrency.Task { @MainActor in
            do {
                let taskId = try await shareRepository.acceptShare(token: token)

                // Fetch the shared task to show its name (uses RPC to bypass tasks RLS)
                let sharedTasks = try await taskRepository.fetchSharedTasks()
                acceptedTaskName = sharedTasks.first(where: { $0.id == taskId })?.title ?? "Shared item"
                showAcceptedAlert = true

                // Notify all views to refresh
                NotificationCenter.default.post(name: .sharedItemsChanged, object: nil)
                NotificationCenter.default.post(name: .projectListChanged, object: nil)
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
