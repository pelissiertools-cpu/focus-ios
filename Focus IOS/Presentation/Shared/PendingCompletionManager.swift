import Foundation

/// Manages grace-period timers for task completion with undo support.
/// Shared across ViewModels to eliminate duplicate pending completion logic.
@MainActor
class PendingCompletionManager {
    static let gracePeriod: Duration = .seconds(1.5)

    private(set) var pendingIds: Set<UUID> = []
    private var timers: [UUID: _Concurrency.Task<Void, Never>] = [:]

    /// Called whenever `pendingIds` changes, so the owning ViewModel can trigger UI updates.
    var onChange: (() -> Void)?

    func isPending(_ id: UUID) -> Bool {
        pendingIds.contains(id)
    }

    /// Schedule a completion after the grace period.
    /// If already pending, cancels it (undo). Returns true if cancelled (undone).
    @discardableResult
    func scheduleCompletion(for id: UUID, action: @escaping @MainActor () async -> Void) -> Bool {
        if pendingIds.contains(id) {
            cancel(id)
            return true
        }

        pendingIds.insert(id)
        onChange?()

        let timer = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: Self.gracePeriod)
            guard !_Concurrency.Task.isCancelled else { return }
            self.pendingIds.remove(id)
            self.timers.removeValue(forKey: id)
            self.onChange?()
            await action()
        }
        timers[id] = timer
        return false
    }

    func cancel(_ id: UUID) {
        timers[id]?.cancel()
        timers.removeValue(forKey: id)
        pendingIds.remove(id)
        onChange?()
    }
}
