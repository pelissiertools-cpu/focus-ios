# Codebase Audit TODO (March 2026)

## Completed
- [x] 1. Move Supabase credentials to gitignored .xcconfig (commit 1de1a7d)
- [x] 2. **Sort order race condition** — Replaced fetch-all-then-max+1 with lightweight `SELECT sort_order ORDER BY DESC LIMIT 1` helpers (`nextSortOrder`, `nextSortOrderByType`). Eliminates fetching entire collections just to compute a sort order.
- [x] 13. **Debug font enumeration in production** — Wrapped in `#if DEBUG`.
- [x] 14. **AppDataCache has no invalidation** — Added `invalidate()` method; called on sign-out in AuthService.
- [x] 15. **checkEmailExists swallows errors** — Returns `Bool?` now; nil on failure so callers can distinguish error from "not found". AuthSheetView updated to handle nil.
- [x] 16. **Singleton @MainActor isolation** — Investigated; `nonisolated(unsafe)` is unnecessary on these singletons under Xcode 16/Swift 6. Compiler already handles them correctly. Not a real issue.
- [x] 17. **Schedule model missing Hashable/Equatable** — Added conformance.
- [x] 19. **Dead code: InboxView.swift** — Deleted. Extracted `PendingScheduleInfo` struct to `Domain/Models/PendingScheduleInfo.swift`.
- [x] 21. **Unused `import Auth`** — False positive. All 3 ViewModels access `authService.currentUser?.id` which requires the Auth module import.

## Remaining Items

### HIGH — Memory Leaks & Crashes
- [ ] 3. **No `deinit` on any ViewModel** — All 7 ViewModels store `pendingCompletionTimers` (Task references) but never cancel on deallocation.
- [ ] 4. **17+ untracked fire-and-forget Tasks** — `_Concurrency.Task { await persistSortOrders(...) }` called without storing references. Worst: FocusTabViewModel (lines 1129, 1230, 1314, 1372, 1443, 1488).
- [ ] 5. **DispatchQueue.main.asyncAfter without cancellation** — FocusTabViewModel:2007-2032, nested asyncAfter blocks.
- [ ] 6. **Notification handler Tasks not tracked** — `.sink` closures spawn untracked Tasks in 6+ ViewModels.

### HIGH — Performance
- [ ] 7. **N+1 subtask fetching** — FocusTabViewModel:299-319 fetches subtasks per-task instead of batch.
- [ ] 8. **N+1 sort order updates** — TaskRepository:343-352, ScheduleRepository:306-326, one UPDATE per item in loop.
- [ ] 9. **Unbounded queries** — No `.limit()` on fetchTasks, fetchProjects, fetchGoals, fetchCategories, fetchScheduleSummaries.

### HIGH — Redundancy
- [ ] 10. **Duplicate pending completion logic** — Identical grace-period timer code in 5 ViewModels.
- [ ] 11. **Redundant ViewModel creation per tab** — TodayView, ScheduledView, BacklogView each create fresh @StateObject ViewModels.
- [ ] 12. **Repeated query-building logic** — TaskRepository repeats same filter pattern across fetchTasks, fetchProjects, fetchGoals.

### MEDIUM
- [ ] 18. **Zero accessibility labels** — No .accessibilityLabel on any interactive element in 60+ views.

### LOW
- [ ] 20. **Hardcoded spacing values** — Literal numbers scattered across 40+ files.
