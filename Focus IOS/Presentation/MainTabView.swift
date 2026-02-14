//
//  MainTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var focusViewModel: FocusTabViewModel

    var body: some View {
        TabView {
            FocusTabView()
                .tabItem {
                    Label("Focus", systemImage: "target")
                }
                .environmentObject(focusViewModel)

            LogTabView()
                .tabItem {
                    Label("Log", systemImage: "tray.full")
                }
                .environmentObject(focusViewModel)
        }
    }
}

#Preview {
    let authService = AuthService()
    MainTabView()
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
