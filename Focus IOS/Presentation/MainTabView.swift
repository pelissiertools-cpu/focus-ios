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
    @StateObject private var homeViewModel = HomeViewModel()

    var body: some View {
        HomeView(viewModel: homeViewModel, authService: authService)
            .environmentObject(focusViewModel)
    }
}

#Preview {
    let auth = AuthService()
    MainTabView()
        .environmentObject(auth)
        .environmentObject(FocusTabViewModel(authService: auth))
}
