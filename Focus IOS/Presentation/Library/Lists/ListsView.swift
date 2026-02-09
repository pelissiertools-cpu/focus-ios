//
//  ListsView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct ListsView: View {
    @ObservedObject var viewModel: ListsViewModel
    let searchText: String

    init(viewModel: ListsViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Lists View")
                    .font(.title2)
                    .padding()

                Text("Coming Soon")
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 44)
    }
}

#Preview {
    ListsView(viewModel: ListsViewModel(authService: AuthService()))
}
