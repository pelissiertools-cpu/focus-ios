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

    init() {
        let tabGray = UIColor(red: 0x6A/255.0, green: 0x6A/255.0, blue: 0x6A/255.0, alpha: 1)
        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance.normal.iconColor = tabGray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: tabGray]
        appearance.stackedLayoutAppearance.selected.iconColor = .label
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FocusTabView(selectedTab: $selectedTab)
                .tabItem {
                    Label {
                        Text("Focus")
                    } icon: {
                        Image("CheckCircle")
                            .renderingMode(.template)
                    }
                }
                .tag(0)
                .environmentObject(focusViewModel)

            LogTabView(mainTab: $selectedTab)
                .tabItem {
                    Label("Log", systemImage: "tray.full")
                }
                .tag(1)
                .environmentObject(focusViewModel)
        }
        .background(TabBarSelectedImageSetter())
    }
}

private struct TabBarSelectedImageSetter: UIViewRepresentable {
    func makeUIView(context: Context) -> TabBarSetterView {
        TabBarSetterView()
    }
    func updateUIView(_ uiView: TabBarSetterView, context: Context) {}
}

private class TabBarSetterView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window = window else { return }
        configureTabBar(in: window)
    }

    private func configureTabBar(in window: UIWindow) {
        guard let tabBar = window.findSubview(ofType: UITabBar.self),
              let items = tabBar.items, items.count >= 2 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let window = self?.window else { return }
                self?.configureTabBar(in: window)
            }
            return
        }
        items[0].selectedImage = UIImage(named: "CheckCircle")?
            .withTintColor(.label, renderingMode: .alwaysOriginal)
        items[1].selectedImage = UIImage(systemName: "tray.full")?
            .withTintColor(.label, renderingMode: .alwaysOriginal)
    }
}

private extension UIView {
    func findSubview<T: UIView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.findSubview(ofType: type) { return found }
        }
        return nil
    }
}

#Preview {
    let authService = AuthService()
    MainTabView()
        .environmentObject(authService)
        .environmentObject(FocusTabViewModel(authService: authService))
}
