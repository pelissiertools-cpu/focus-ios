//
//  LibraryTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct LibraryTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Picker for Tasks/Projects/Lists
                Picker("Library Type", selection: $selectedTab) {
                    Text("Tasks").tag(0)
                    Text("Projects").tag(1)
                    Text("Lists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selection
                Group {
                    switch selectedTab {
                    case 0:
                        TasksListView()
                    case 1:
                        ProjectsListView()
                    case 2:
                        ListsView()
                    default:
                        TasksListView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Library")
        }
    }
}

#Preview {
    LibraryTabView()
}
