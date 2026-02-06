//
//  MainTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var focusViewModel = FocusTabViewModel(authService: AuthService())

    var body: some View {
        TabView {
            LibraryTabView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .environmentObject(focusViewModel)

            FocusTabView()
                .tabItem {
                    Label("Focus", systemImage: "target")
                }
                .environmentObject(focusViewModel)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
