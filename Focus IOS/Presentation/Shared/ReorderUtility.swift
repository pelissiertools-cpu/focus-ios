//
//  ReorderUtility.swift
//  Focus IOS
//

import Foundation

/// Pure reorder utilities for FocusTask arrays and maps.
/// These compute new sort orders without side effects.
@MainActor
enum ReorderUtility {

    /// Reorder items within a flat array.
    /// Filters to uncompleted items (by default), moves `droppedId` to `targetId`'s position,
    /// then writes back updated sortOrders into `items`.
    /// Returns the list of (id, sortOrder) updates for persistence, or nil if no-op.
    @discardableResult
    static func reorderItems(
        _ items: inout [FocusTask],
        droppedId: UUID,
        targetId: UUID,
        filterCompleted: Bool = true
    ) -> [(id: UUID, sortOrder: Int)]? {
        var working: [FocusTask]
        if filterCompleted {
            working = items.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            working = items.sorted { $0.sortOrder < $1.sortOrder }
        }

        guard let fromIndex = working.firstIndex(where: { $0.id == droppedId }),
              let toIndex = working.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return nil }

        let moved = working.remove(at: fromIndex)
        working.insert(moved, at: toIndex)

        // Write back sort orders into the original items array
        for (index, item) in working.enumerated() {
            if let originalIndex = items.firstIndex(where: { $0.id == item.id }) {
                items[originalIndex].sortOrder = index
            }
        }

        return working.enumerated().map { (index, item) in
            (id: item.id, sortOrder: index)
        }
    }

    /// Reorder child items within a map entry (e.g., subtasksMap[parentId]).
    /// Filters to uncompleted children, moves droppedId to targetId's position,
    /// then writes back updated sortOrders into the map entry.
    /// Returns the list of (id, sortOrder) updates for persistence, or nil if no-op.
    @discardableResult
    static func reorderChildItems(
        in map: inout [UUID: [FocusTask]],
        parentId: UUID,
        droppedId: UUID,
        targetId: UUID
    ) -> [(id: UUID, sortOrder: Int)]? {
        guard var allChildren = map[parentId] else { return nil }
        var uncompleted = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

        guard let fromIndex = uncompleted.firstIndex(where: { $0.id == droppedId }),
              let toIndex = uncompleted.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return nil }

        let moved = uncompleted.remove(at: fromIndex)
        uncompleted.insert(moved, at: toIndex)

        // Write back sort orders into the full children array
        for (index, child) in uncompleted.enumerated() {
            if let mapIndex = allChildren.firstIndex(where: { $0.id == child.id }) {
                allChildren[mapIndex].sortOrder = index
            }
        }
        map[parentId] = allChildren

        return uncompleted.enumerated().map { (index, child) in
            (id: child.id, sortOrder: index)
        }
    }
}
