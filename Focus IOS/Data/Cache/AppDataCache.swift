//
//  AppDataCache.swift
//  Focus IOS
//

import Foundation

@MainActor
final class AppDataCache {
    static let shared = AppDataCache()

    // Tasks (raw result from fetchTasks — includes both parent and subtasks)
    var allTasks: [FocusTask] = []
    var hasLoadedTasks = false

    // Categories
    var categories: [Category] = []
    var hasLoadedCategories = false

    // Projects
    var projects: [FocusTask] = []
    var hasLoadedProjects = false

    // Lists
    var lists: [FocusTask] = []
    var hasLoadedLists = false

    // Schedule summaries + derived scheduledTaskIds
    var scheduleSummaries: [ScheduleRepository.ScheduleSummary] = []
    var scheduledTaskIds: Set<UUID> = []
    var hasLoadedScheduleSummaries = false

    // Today schedule data (cached per-day)
    var todayFocusSchedules: [Schedule] = []
    var todayTodoSchedules: [Schedule] = []
    var overdueSchedules: [Schedule] = []
    var todayScheduleDate: Date? = nil

    private init() {}
}
