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
        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.label
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

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
        .background(TabBarSelectedImageSetter())
    }
}

private struct TabBarSelectedImageSetter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let window = uiView.window,
                  let tabBar = window.findSubview(ofType: UITabBar.self),
                  let items = tabBar.items, items.count >= 2
            else { return }
            items[0].selectedImage = UIImage(systemName: "target")?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            items[1].selectedImage = UIImage(systemName: "tray.full")?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        }
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
