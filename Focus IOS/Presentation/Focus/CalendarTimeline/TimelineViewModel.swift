//
//  TimelineViewModel.swift
//  Focus IOS
//

import SwiftUI
import Combine
import Auth

// MARK: - Schedule Drag Info

struct ScheduleDragInfo {
    let taskId: UUID
    let commitmentId: UUID?
    let taskTitle: String
    let isCompleted: Bool
    let subtaskText: String?
}

// MARK: - Timeline ViewModel

@MainActor
class TimelineViewModel: ObservableObject {
    // Parent reference (unowned — parent always outlives us)
    unowned let parent: FocusTabViewModel

    // Timeline scheduled commitments
    @Published var timedCommitments: [Commitment] = []

    // Timeline schedule drag state (drawer-to-timeline drag)
    @Published var scheduleDragInfo: ScheduleDragInfo? = nil
    @Published var scheduleDragLocation: CGPoint = .zero
    @Published var isTimelineDropTargeted: Bool = false
    @Published var timelineDropPreviewY: CGFloat = 0
    @Published var isDrawerRetractedForDrag: Bool = false
    @Published var isDragOverCancelZone: Bool = false
    var cancelZoneGlobalMinY: CGFloat = 0    // Cancel bar top edge in global coords
    var timelineContentOriginY: CGFloat = 0  // Content ZStack origin in global coordinate space
    var timelineScrollOffset: CGFloat = 0    // ScrollView contentOffset.y (for future use)
    var drawerTopGlobalY: CGFloat = 0        // Drawer top edge in global coords

    // Timeline block interaction state (move/resize existing blocks)
    @Published var timelineBlockDragId: UUID?  // commitment ID being moved
    private var blockMoveOriginalY: CGFloat?  // original Y position of block being moved
    private var resizeOriginalDuration: Int?  // original duration before resize started
    private var resizeOriginalTime: Date?  // original scheduledTime before top-resize started
    var timelineCreatedCommitmentIds: Set<UUID> = []  // commitments created from log drag (no prior commitment)

    private let commitmentRepository: CommitmentRepository
    private let taskRepository: TaskRepository
    private let authService: AuthService

    private let hourHeight: CGFloat = 60  // matches TimelineGridView.hourHeight

    init(parent: FocusTabViewModel,
         commitmentRepository: CommitmentRepository,
         taskRepository: TaskRepository,
         authService: AuthService) {
        self.parent = parent
        self.commitmentRepository = commitmentRepository
        self.taskRepository = taskRepository
        self.authService = authService
    }

    // MARK: - Calendar Timeline Methods

    /// Fetch commitments with a scheduled time for the selected date
    func fetchTimedCommitments() async {
        do {
            timedCommitments = try await commitmentRepository.fetchTimedCommitments(for: parent.selectedDate)

            // Ensure tasks are loaded in tasksMap
            let missingIds = timedCommitments.map { $0.taskId }.filter { parent.tasksMap[$0] == nil }
            if !missingIds.isEmpty {
                let tasks = try await taskRepository.fetchTasksByIds(missingIds)
                for task in tasks {
                    parent.tasksMap[task.id] = task
                }
            }
        } catch {
            parent.errorMessage = error.localizedDescription
        }
    }

    /// Assign a scheduled time to an existing commitment
    func scheduleCommitmentTime(_ commitmentId: UUID, at time: Date, durationMinutes: Int = 30) async {
        do {
            try await commitmentRepository.updateCommitmentTime(
                id: commitmentId,
                scheduledTime: time,
                durationMinutes: durationMinutes
            )

            // Update local state
            if let index = parent.commitments.firstIndex(where: { $0.id == commitmentId }) {
                parent.commitments[index].scheduledTime = time
                parent.commitments[index].durationMinutes = durationMinutes
            }

            await fetchTimedCommitments()
        } catch {
            parent.errorMessage = error.localizedDescription
        }
    }

    /// Create a new timed commitment for a log task dragged onto the timeline
    func createTimedCommitment(taskId: UUID, at time: Date) async {
        guard let userId = authService.currentUser?.id else {
            parent.errorMessage = "No authenticated user"
            return
        }

        do {
            let commitment = Commitment(
                userId: userId,
                taskId: taskId,
                timeframe: .daily,
                section: .todo,
                commitmentDate: parent.selectedDate,
                sortOrder: 0,
                scheduledTime: time,
                durationMinutes: 30
            )
            let created = try await commitmentRepository.createCommitment(commitment)
            parent.commitments.append(created)
            timelineCreatedCommitmentIds.insert(created.id)
            await fetchTimedCommitments()
        } catch {
            parent.errorMessage = error.localizedDescription
        }
    }

    /// Convert a Y-position on the timeline to a Date with time, snapped to 15-min intervals
    func timeFromYPosition(_ y: CGFloat, on date: Date) -> Date {
        let totalMinutes = (y / hourHeight) * 60
        let snappedMinutes = Int((totalMinutes / 15.0).rounded()) * 15
        let hour = min(max(snappedMinutes / 60, 0), 23)
        let minute = min(snappedMinutes % 60, 59)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? date
    }

    // MARK: - Timeline Block Move (long-press drag to reposition)

    /// Convert a scheduled time to its Y position on the timeline grid
    private func yPositionFromTime(_ time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        return CGFloat(hour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
    }

    func handleTimelineBlockMoveChanged(translationHeight: CGFloat, commitment: Commitment, task: FocusTask) {
        if timelineBlockDragId == nil {
            timelineBlockDragId = commitment.id
        }

        // Capture original Y position on drag start
        if blockMoveOriginalY == nil, let time = commitment.scheduledTime {
            blockMoveOriginalY = yPositionFromTime(time)
        }

        // Reuse existing drag infrastructure for drop preview
        if scheduleDragInfo == nil {
            scheduleDragInfo = ScheduleDragInfo(taskId: task.id, commitmentId: commitment.id, taskTitle: task.title, isCompleted: task.isCompleted, subtaskText: nil)
        }

        let newY = (blockMoveOriginalY ?? 0) + translationHeight
        timelineDropPreviewY = max(0, newY)
        isTimelineDropTargeted = true
    }

    func handleTimelineBlockMoveEnded(translationHeight: CGFloat) {
        let finalY = max(0, (blockMoveOriginalY ?? 0) + translationHeight)

        if let info = scheduleDragInfo, let commitmentId = info.commitmentId {
            let dropTime = timeFromYPosition(finalY, on: parent.selectedDate)
            let duration = timedCommitments.first(where: { $0.id == commitmentId })?.durationMinutes ?? 30
            _Concurrency.Task { @MainActor in
                await scheduleCommitmentTime(commitmentId, at: dropTime, durationMinutes: duration)
            }
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            timelineBlockDragId = nil
            scheduleDragInfo = nil
            isTimelineDropTargeted = false
        }
        blockMoveOriginalY = nil
    }

    // MARK: - Timeline Block Resize (drag top/bottom handles)

    /// Convert a vertical drag delta (points) to minutes, snapped to 15-min intervals
    private func deltaToSnappedMinutes(_ delta: CGFloat) -> Int {
        let rawMinutes = (delta / hourHeight) * 60
        return (Int(rawMinutes) / 15) * 15
    }

    func handleTimelineBlockBottomResizeChanged(commitmentId: UUID, dragDelta: CGFloat) {
        guard let index = timedCommitments.firstIndex(where: { $0.id == commitmentId }) else { return }

        if resizeOriginalDuration == nil {
            resizeOriginalDuration = timedCommitments[index].durationMinutes ?? 30
            timelineBlockDragId = commitmentId
        }

        let deltaMinutes = deltaToSnappedMinutes(dragDelta)
        let newDuration = max(15, (resizeOriginalDuration ?? 30) + deltaMinutes)
        timedCommitments[index].durationMinutes = newDuration
    }

    func handleTimelineBlockBottomResizeEnded(commitmentId: UUID, dragDelta: CGFloat) {
        guard let index = timedCommitments.firstIndex(where: { $0.id == commitmentId }) else {
            resetResizeState()
            return
        }

        let deltaMinutes = deltaToSnappedMinutes(dragDelta)
        let newDuration = max(15, (resizeOriginalDuration ?? 30) + deltaMinutes)
        timedCommitments[index].durationMinutes = newDuration

        let scheduledTime = timedCommitments[index].scheduledTime
        _Concurrency.Task { @MainActor in
            do {
                try await commitmentRepository.updateCommitmentTime(
                    id: commitmentId, scheduledTime: scheduledTime, durationMinutes: newDuration
                )
            } catch {
                parent.errorMessage = "Failed to resize: \(error.localizedDescription)"
                await fetchTimedCommitments()
            }
        }

        resetResizeState()
    }

    func handleTimelineBlockTopResizeChanged(commitmentId: UUID, dragDelta: CGFloat) {
        guard let index = timedCommitments.firstIndex(where: { $0.id == commitmentId }) else { return }

        if resizeOriginalDuration == nil {
            resizeOriginalDuration = timedCommitments[index].durationMinutes ?? 30
            resizeOriginalTime = timedCommitments[index].scheduledTime
            timelineBlockDragId = commitmentId
        }

        let deltaMinutes = deltaToSnappedMinutes(dragDelta)
        let newDuration = max(15, (resizeOriginalDuration ?? 30) - deltaMinutes)
        let newTime = resizeOriginalTime?.addingTimeInterval(Double(deltaMinutes) * 60)

        timedCommitments[index].durationMinutes = newDuration
        timedCommitments[index].scheduledTime = newTime
    }

    func handleTimelineBlockTopResizeEnded(commitmentId: UUID, dragDelta: CGFloat) {
        guard let index = timedCommitments.firstIndex(where: { $0.id == commitmentId }) else {
            resetResizeState()
            return
        }

        let deltaMinutes = deltaToSnappedMinutes(dragDelta)
        let newDuration = max(15, (resizeOriginalDuration ?? 30) - deltaMinutes)
        let newTime = resizeOriginalTime?.addingTimeInterval(Double(deltaMinutes) * 60)

        timedCommitments[index].durationMinutes = newDuration
        timedCommitments[index].scheduledTime = newTime

        _Concurrency.Task { @MainActor in
            do {
                try await commitmentRepository.updateCommitmentTime(
                    id: commitmentId, scheduledTime: newTime, durationMinutes: newDuration
                )
            } catch {
                parent.errorMessage = "Failed to resize: \(error.localizedDescription)"
                await fetchTimedCommitments()
            }
        }

        resetResizeState()
    }

    private func resetResizeState() {
        withAnimation(.easeInOut(duration: 0.15)) {
            timelineBlockDragId = nil
        }
        resizeOriginalDuration = nil
        resizeOriginalTime = nil
    }

    // MARK: - Unschedule (remove from timeline)

    func unscheduleCommitment(_ commitmentId: UUID) async {
        // Optimistic: remove from timeline UI
        timedCommitments.removeAll { $0.id == commitmentId }

        if timelineCreatedCommitmentIds.contains(commitmentId) {
            // Log-originated: delete the entire commitment (no prior commitment existed)
            timelineCreatedCommitmentIds.remove(commitmentId)

            guard let commitment = parent.commitments.first(where: { $0.id == commitmentId }) else {
                do {
                    try await commitmentRepository.deleteCommitment(id: commitmentId)
                } catch {
                    parent.errorMessage = "Failed to unschedule: \(error.localizedDescription)"
                    await fetchTimedCommitments()
                }
                return
            }

            do {
                try await parent.deleteCommitmentWithDescendants(commitment)
            } catch {
                parent.errorMessage = "Failed to unschedule: \(error.localizedDescription)"
                await fetchTimedCommitments()
            }
        } else {
            // Focus-originated: just clear the time, keep commitment
            if let index = parent.commitments.firstIndex(where: { $0.id == commitmentId }) {
                parent.commitments[index].scheduledTime = nil
                parent.commitments[index].durationMinutes = nil
            }

            do {
                try await commitmentRepository.updateCommitmentTime(
                    id: commitmentId, scheduledTime: nil, durationMinutes: nil
                )
            } catch {
                parent.errorMessage = "Failed to unschedule: \(error.localizedDescription)"
                await fetchTimedCommitments()
            }
        }
    }

    // MARK: - Schedule Drag Helpers (drawer-to-timeline drag)

    func handleScheduleDragChanged(location: CGPoint, taskId: UUID, commitmentId: UUID?, taskTitle: String, isCompleted: Bool = false, subtaskText: String? = nil) {
        if scheduleDragInfo == nil {
            scheduleDragInfo = ScheduleDragInfo(taskId: taskId, commitmentId: commitmentId, taskTitle: taskTitle, isCompleted: isCompleted, subtaskText: subtaskText)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        scheduleDragLocation = location

        // Retract drawer when drag crosses above its top edge
        let shouldRetract = location.y < drawerTopGlobalY
        if shouldRetract != isDrawerRetractedForDrag {
            withAnimation(.easeInOut(duration: 0.25)) {
                isDrawerRetractedForDrag = shouldRetract
            }
        }

        // Check if over cancel zone (the retracted bar at bottom)
        if isDrawerRetractedForDrag && cancelZoneGlobalMinY > 0 {
            let overCancel = location.y >= cancelZoneGlobalMinY
            if overCancel != isDragOverCancelZone {
                isDragOverCancelZone = overCancel
                if overCancel {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        } else {
            isDragOverCancelZone = false
        }

        let contentY = location.y - timelineContentOriginY
        timelineDropPreviewY = max(0, contentY)
        isTimelineDropTargeted = contentY >= 0 && !isDragOverCancelZone
    }

    func handleScheduleDragEnded(location: CGPoint) {
        // If dropped on cancel zone, just cancel — don't schedule
        let cancelled = isDragOverCancelZone

        if !cancelled {
            let contentY = location.y - timelineContentOriginY

            if contentY >= 0, let info = scheduleDragInfo {
                let dropTime = timeFromYPosition(max(0, contentY), on: parent.selectedDate)

                _Concurrency.Task { @MainActor in
                    if let commitmentId = info.commitmentId {
                        let duration = timedCommitments.first(where: { $0.id == commitmentId })?.durationMinutes ?? 30
                        await scheduleCommitmentTime(commitmentId, at: dropTime, durationMinutes: duration)
                    } else {
                        await createTimedCommitment(taskId: info.taskId, at: dropTime)
                    }
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            scheduleDragInfo = nil
            isTimelineDropTargeted = false
            isDrawerRetractedForDrag = false
            isDragOverCancelZone = false
        }
        scheduleDragLocation = .zero
        cancelZoneGlobalMinY = 0
    }
}
