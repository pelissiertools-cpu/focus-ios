//
//  RealtimeService.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-03-13.
//

import Foundation
import Supabase
import Combine

@MainActor
final class RealtimeService {
    static let shared = RealtimeService()

    private let supabase = SupabaseClientManager.shared.client
    private var channel: RealtimeChannelV2?
    private var listenerTasks: [_Concurrency.Task<Void, Never>] = []

    // Debounce subjects to collapse rapid-fire events
    private let taskChangeSubject = PassthroughSubject<Void, Never>()
    private let scheduleChangeSubject = PassthroughSubject<Void, Never>()
    private let categoryChangeSubject = PassthroughSubject<Void, Never>()
    private let shareChangeSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDebouncing()
    }

    // MARK: - Debouncing

    private func setupDebouncing() {
        taskChangeSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.postTaskChangeNotifications()
            }
            .store(in: &cancellables)

        scheduleChangeSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink {
                NotificationCenter.default.post(name: .schedulesChanged, object: nil)
            }
            .store(in: &cancellables)

        categoryChangeSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink {
                NotificationCenter.default.post(name: .projectListChanged, object: nil)
            }
            .store(in: &cancellables)

        shareChangeSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink {
                NotificationCenter.default.post(name: .sharedItemsChanged, object: nil)
                NotificationCenter.default.post(name: .projectListChanged, object: nil)
            }
            .store(in: &cancellables)
    }

    private func postTaskChangeNotifications() {
        NotificationCenter.default.post(name: .realtimeTasksChanged, object: nil)
        NotificationCenter.default.post(name: .projectListChanged, object: nil)
    }

    // MARK: - Lifecycle

    func connect(userId: UUID) async {
        await disconnect()

        let channel = supabase.realtimeV2.channel("db-changes")

        // No explicit user_id filter — Supabase RLS handles access control.
        // This ensures changes by OTHER users in shared projects/lists are also received.
        let taskChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "tasks"
        )

        let scheduleChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "schedules"
        )

        let categoryChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "categories",
            filter: .eq("user_id", value: userId)
        )

        // Listen for shares where I'm the owner (someone accepted my share)
        let shareOwnerChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "task_shares",
            filter: .eq("owner_id", value: userId)
        )

        // Listen for shares where I'm the recipient (someone shared with me)
        let shareRecipientChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "task_shares",
            filter: .eq("shared_with_user_id", value: userId)
        )

        self.channel = channel
        try? await channel.subscribeWithError()

        let taskListener = _Concurrency.Task { @MainActor [weak self] in
            for await _ in taskChanges {
                self?.taskChangeSubject.send()
            }
        }

        let scheduleListener = _Concurrency.Task { @MainActor [weak self] in
            for await _ in scheduleChanges {
                self?.scheduleChangeSubject.send()
            }
        }

        let categoryListener = _Concurrency.Task { @MainActor [weak self] in
            for await _ in categoryChanges {
                self?.categoryChangeSubject.send()
            }
        }

        let shareOwnerListener = _Concurrency.Task { @MainActor [weak self] in
            for await _ in shareOwnerChanges {
                self?.shareChangeSubject.send()
            }
        }

        let shareRecipientListener = _Concurrency.Task { @MainActor [weak self] in
            for await _ in shareRecipientChanges {
                self?.shareChangeSubject.send()
            }
        }

        listenerTasks = [taskListener, scheduleListener, categoryListener, shareOwnerListener, shareRecipientListener]
    }

    func disconnect() async {
        for task in listenerTasks {
            task.cancel()
        }
        listenerTasks = []

        if let channel {
            await channel.unsubscribe()
        }
        channel = nil
    }
}
