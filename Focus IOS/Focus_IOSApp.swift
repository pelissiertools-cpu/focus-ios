//
//  Focus_IOSApp.swift
//  Focus IOS
//
//  Created by Gabriel  on 2026-02-04.
//

import SwiftUI
import CoreData

@main
struct Focus_IOSApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
