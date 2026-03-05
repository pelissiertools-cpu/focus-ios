//
//  HomeViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

enum HomeMenuItem: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case assign = "Scheduled"
    case unassign = "Backlog"
    case braindump = "Braindump"
    case archive = "Archive"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .today:     return "sun.max"
        case .assign:    return "calendar"
        case .unassign:  return "tray"
        case .braindump: return "brain.head.profile"
        case .archive:   return "archivebox"
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var projects: [FocusTask] = []
    @Published var lists: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Navigation state
    @Published var selectedMenuItem: HomeMenuItem?
    @Published var selectedProject: FocusTask?
    @Published var selectedList: FocusTask?

    private let repository: TaskRepository
    private let commitmentRepository = CommitmentRepository()
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService) {
        self.repository = TaskRepository()
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .projectListChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchProjects()
                    await self.fetchLists()
                }
            }
            .store(in: &cancellables)
    }

    func fetchProjects(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        do {
            let allProjects = try await repository.fetchProjects()
            projects = allProjects.filter { !$0.isCompleted }
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading { isLoading = false }
    }

    func fetchLists() async {
        do {
            let allLists = try await repository.fetchTasks(ofType: .list)
            lists = allLists.filter { !$0.isCleared && !$0.isCompleted }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: FocusTask) async {
        do {
            try await repository.deleteTask(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: FocusTask) async {
        do {
            try await repository.deleteTask(id: list.id)
            lists.removeAll { $0.id == list.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reorder

    func reorderProjects(from source: IndexSet, to destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, project) in projects.enumerated() {
            projects[index].sortOrder = index
            updates.append((id: project.id, sortOrder: index))
        }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    func reorderLists(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, list) in lists.enumerated() {
            lists[index].sortOrder = index
            updates.append((id: list.id, sortOrder: index))
        }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }
}
