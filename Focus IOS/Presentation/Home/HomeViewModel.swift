//
//  HomeViewModel.swift
//  Focus IOS
//

import Foundation
import Combine

enum HomeMenuItem: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case upcoming = "Upcoming"
    case unassign = "Unassign"
    case assign = "Assign"
    case braindump = "Braindump"
    case archive = "Archive"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .today:     return "sun.max"
        case .upcoming:  return "calendar"
        case .unassign:  return "tray"
        case .assign:    return "tray.full"
        case .braindump: return "brain.head.profile"
        case .archive:   return "archivebox"
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var projects: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Navigation state
    @Published var selectedMenuItem: HomeMenuItem?
    @Published var selectedProject: FocusTask?

    private let repository: TaskRepository
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
                }
            }
            .store(in: &cancellables)
    }

    func fetchProjects() async {
        isLoading = true
        do {
            let allProjects = try await repository.fetchProjects()
            projects = allProjects.filter { !$0.isCompleted }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
