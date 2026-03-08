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

    // Goals
    var goals: [FocusTask] = []
    var hasLoadedGoals = false

    // Schedule summaries + derived scheduledTaskIds
    var scheduleSummaries: [ScheduleRepository.ScheduleSummary] = []
    var scheduledTaskIds: Set<UUID> = []
    var hasLoadedScheduleSummaries = false

    // Today schedule data (cached per-day)
    var todayFocusSchedules: [Schedule] = []
    var todayTodoSchedules: [Schedule] = []
    var overdueSchedules: [Schedule] = []
    var todayScheduleDate: Date? = nil

    /// Reset all cached data (call on sign-out or account switch)
    func invalidate() {
        allTasks = []
        hasLoadedTasks = false
        categories = []
        hasLoadedCategories = false
        projects = []
        hasLoadedProjects = false
        lists = []
        hasLoadedLists = false
        goals = []
        hasLoadedGoals = false
        scheduleSummaries = []
        scheduledTaskIds = []
        hasLoadedScheduleSummaries = false
        todayFocusSchedules = []
        todayTodoSchedules = []
        overdueSchedules = []
        todayScheduleDate = nil
    }

    private init() {}
}
