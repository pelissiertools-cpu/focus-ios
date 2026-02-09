//
//  ListsView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct ListsView: View {
    let searchText: String

    init(searchText: String = "") {
        self.searchText = searchText
    }

    var body: some View {
        VStack {
            Text("Lists View")
                .font(.title2)
                .padding()

            Text("Coming Soon")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ListsView()
}
