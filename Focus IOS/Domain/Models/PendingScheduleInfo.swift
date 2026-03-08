//
//  PendingScheduleInfo.swift
//  Focus IOS
//

import Foundation

struct PendingScheduleInfo {
    let taskId: UUID
    let userId: UUID
    var timeframe: Timeframe
    var section: Section
    var dates: Set<Date>
}
