//
//  KeyboardDismissOverlay.swift
//  Focus IOS
//

import SwiftUI

struct KeyboardDismissOverlay: ViewModifier {
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
        ZStack {
            content

            if isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            }
        }
    }
}

extension View {
    func keyboardDismissOverlay(isActive: Binding<Bool>) -> some View {
        modifier(KeyboardDismissOverlay(isActive: isActive))
    }
}
