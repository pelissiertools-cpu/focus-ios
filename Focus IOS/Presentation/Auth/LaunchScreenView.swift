//
//  LaunchScreenView.swift
//  Focus IOS
//

import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            Text("Focus")
                .font(.inter(size: 48, weight: .bold))
                .foregroundColor(.black)
        }
    }
}
