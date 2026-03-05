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
    @StateObject private var homeViewModel = HomeViewModel(authService: AuthService())

    var body: some View {
        HomeView(viewModel: homeViewModel)
            .environmentObject(focusViewModel)
    }
}

#Preview {
    let authService = AuthService()
    MainTabView()
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
