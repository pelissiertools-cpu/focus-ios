//
//  LibraryTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct LibraryTabView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                .padding(.horizontal)
                .padding(.top, 8)

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
                        TasksListView(searchText: searchText)
                    case 1:
                        ProjectsListView(searchText: searchText)
                    case 2:
                        ListsView(searchText: searchText)
                    default:
                        TasksListView(searchText: searchText)
                    }
                }
                .frame(maxHeight: .infinity)
                .onTapGesture {
                    isSearchFocused = false
                }
            }
            .onChange(of: selectedTab) { _, _ in
                searchText = ""
                isSearchFocused = false
            }
        }
    }
}

#Preview {
    LibraryTabView()
}
