//
//  KeyboardDismissOverlay.swift
//  Focus IOS
//

import SwiftUI

struct KeyboardDismissOverlay: ViewModifier {
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    TapToDismissView()
                        .ignoresSafeArea(.keyboard)
                }
            }
    }
}

/// A UIKit-backed tap recognizer that dismisses the keyboard
/// without blocking scroll gestures.
private struct TapToDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismiss))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        @objc func dismiss() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }
}

extension View {
    func keyboardDismissOverlay(isActive: Binding<Bool>) -> some View {
        modifier(KeyboardDismissOverlay(isActive: isActive))
    }
}
