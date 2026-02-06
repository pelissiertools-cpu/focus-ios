//
//  FocusTabViewModel.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import Foundation
import Combine

@MainActor
class FocusTabViewModel: ObservableObject {
    @Published var commitments: [Commitment] = []
    @Published var tasksMap: [UUID: FocusTask] = [:]  // taskId -> task
    @Published var selectedTimeframe: Timeframe = .daily
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let commitmentRepository: CommitmentRepository
    private let taskRepository: TaskRepository
    private let authService: AuthService

    init(commitmentRepository: CommitmentRepository = CommitmentRepository(),
         taskRepository: TaskRepository = TaskRepository(),
         authService: AuthService) {
        self.commitmentRepository = commitmentRepository
        self.taskRepository = taskRepository
        self.authService = authService
    }

    /// Fetch commitments for selected timeframe and date
    func fetchCommitments() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch both focus and extra sections
            let focusCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .focus
            )
            let extraCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: selectedTimeframe,
                date: selectedDate,
                section: .extra
            )

            self.commitments = focusCommitments + extraCommitments

            // Fetch associated tasks
            await fetchTasksForCommitments()

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Fetch task details for all commitments
    private func fetchTasksForCommitments() async {
        let taskIds = Set(commitments.map { $0.taskId })
        for taskId in taskIds {
            do {
                let tasks = try await taskRepository.fetchTasks()
                if let task = tasks.first(where: { $0.id == taskId }) {
                    tasksMap[taskId] = task
                }
            } catch {
                print("Error fetching task \(taskId): \(error)")
            }
        }
    }

    /// Check if commitment date matches selected timeframe and date
    private func isSameTimeframe(_ commitmentDate: Date, timeframe: Timeframe, selectedDate: Date) -> Bool {
        let calendar = Calendar.current
        switch timeframe {
        case .daily:
            return calendar.isDate(commitmentDate, inSameDayAs: selectedDate)
        case .weekly:
            let commitmentWeek = calendar.component(.weekOfYear, from: commitmentDate)
            let selectedWeek = calendar.component(.weekOfYear, from: selectedDate)
            let commitmentYear = calendar.component(.year, from: commitmentDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return commitmentWeek == selectedWeek && commitmentYear == selectedYear
        case .monthly:
            let commitmentMonth = calendar.component(.month, from: commitmentDate)
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let commitmentYear = calendar.component(.year, from: commitmentDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return commitmentMonth == selectedMonth && commitmentYear == selectedYear
        case .yearly:
            let commitmentYear = calendar.component(.year, from: commitmentDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return commitmentYear == selectedYear
        }
    }

    /// Check if can add more tasks to section
    func canAddTask(to section: Section) -> Bool {
        let currentCount = commitments.filter {
            $0.section == section &&
            $0.timeframe == selectedTimeframe &&
            isSameTimeframe($0.commitmentDate, timeframe: selectedTimeframe, selectedDate: selectedDate)
        }.count

        let maxTasks = section.maxTasks(for: selectedTimeframe)
        return maxTasks == nil || currentCount < maxTasks!
    }

    /// Get current task count for section
    func taskCount(for section: Section) -> Int {
        commitments.filter {
            $0.section == section &&
            $0.timeframe == selectedTimeframe &&
            isSameTimeframe($0.commitmentDate, timeframe: selectedTimeframe, selectedDate: selectedDate)
        }.count
    }

    /// Remove commitment
    func removeCommitment(_ commitment: Commitment) async {
        do {
            try await commitmentRepository.deleteCommitment(id: commitment.id)
            commitments.removeAll { $0.id == commitment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
