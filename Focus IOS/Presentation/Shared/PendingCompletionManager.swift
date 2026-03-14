import Foundation

/// Manages grace-period timers for task completion with undo support.
/// Shared across ViewModels to eliminate duplicate pending completion logic.
@MainActor
class PendingCompletionManager {
    static let gracePeriod: Duration = .seconds(1.5)

    private(set) var pendingIds: Set<UUID> = []
    private var timers: [UUID: _Concurrency.Task<Void, Never>] = [:]
    /// Lightweight fallback actions that capture the repository directly (no weak self).
    /// These survive ViewModel deallocation so completions are never lost.
    private var fallbackActions: [UUID: () async -> Void] = [:]

    /// Called whenever `pendingIds` changes, so the owning ViewModel can trigger UI updates.
    var onChange: (() -> Void)?

    func isPending(_ id: UUID) -> Bool {
        pendingIds.contains(id)
    }

    /// Schedule a completion after the grace period.
    /// If already pending, cancels it (undo). Returns true if cancelled (undone).
    /// - Parameters:
    ///   - id: The task ID
    ///   - action: Full action with ViewModel updates (may capture weak self).
    ///     Must return `true` if it executed successfully.
    ///   - fallback: Lightweight DB-only action that captures the repository directly,
    ///     used when the ViewModel is deallocated before the grace period expires.
    @discardableResult
    func scheduleCompletion(
        for id: UUID,
        action: @escaping @MainActor () async -> Bool,
        fallback: @escaping () async -> Void
    ) -> Bool {
        if pendingIds.contains(id) {
            cancel(id)
            return true
        }

        pendingIds.insert(id)
        fallbackActions[id] = fallback
        onChange?()

        let timer = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: Self.gracePeriod)
            guard !_Concurrency.Task.isCancelled else { return }
            self.pendingIds.remove(id)
            self.timers.removeValue(forKey: id)
            let fallback = self.fallbackActions.removeValue(forKey: id)
            self.onChange?()
            let didExecute = await action()
            if !didExecute {
                await fallback?()
            }
        }
        timers[id] = timer
        return false
    }

    func cancel(_ id: UUID) {
        timers[id]?.cancel()
        timers.removeValue(forKey: id)
        fallbackActions.removeValue(forKey: id)
        pendingIds.remove(id)
        onChange?()
    }

    /// Immediately execute all pending completions using their fallback actions.
    /// Call this when the owning ViewModel is about to be deallocated.
    func flushAll() {
        let pending = fallbackActions
        for (id, timer) in timers {
            timer.cancel()
            timers.removeValue(forKey: id)
        }
        pendingIds.removeAll()
        fallbackActions.removeAll()
        onChange?()
        for (_, fallback) in pending {
            _Concurrency.Task { await fallback() }
        }
    }
}
