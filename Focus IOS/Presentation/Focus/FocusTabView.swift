//
//  FocusTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct FocusTabView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Focus View")
                    .font(.title2)
                    .padding()

                Text("Coming Soon")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Focus")
        }
    }
}

#Preview {
    FocusTabView()
}
