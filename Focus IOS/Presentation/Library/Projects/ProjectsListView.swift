//
//  ProjectsListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct ProjectsListView: View {
    let searchText: String

    init(searchText: String = "") {
        self.searchText = searchText
    }

    var body: some View {
        VStack {
            Text("Projects List")
                .font(.title2)
                .padding()

            Text("Coming Soon")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ProjectsListView()
}
