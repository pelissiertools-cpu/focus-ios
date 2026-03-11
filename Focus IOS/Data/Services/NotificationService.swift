//
//  NotificationService.swift
//  Focus IOS
//

import Foundation
import UserNotifications

@MainActor
class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleNotification(taskId: UUID, title: String, date: Date) {
        // Don't schedule if user has disabled notifications
        guard NotificationManager.shared.isEnabled else { return }
        // Don't schedule notifications in the past
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = formatNotificationDate(date)
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: taskId.uuidString,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelNotification(taskId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [taskId.uuidString])
    }

    func cancelAllNotifications(taskIds: [UUID]) {
        center.removePendingNotificationRequests(withIdentifiers: taskIds.map { $0.uuidString })
    }

    private func formatNotificationDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeString = timeFormatter.string(from: date)

        if cal.isDateInToday(date) {
            return "Today, \(timeString)"
        } else if cal.isDateInTomorrow(date) {
            return "Tomorrow, \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, \(timeString)"
            return dateFormatter.string(from: date)
        }
    }
}

extension Notification.Name {
    static let notificationTappedNavigateToday = Notification.Name("notificationTappedNavigateToday")
}
