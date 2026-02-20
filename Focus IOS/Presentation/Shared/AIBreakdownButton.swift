//
//  AIBreakdownButton.swift
//  Focus IOS
//

import SwiftUI

/// Reusable AI "Break Down task" / "Regenerate" capsule button with glow effect.
/// Used in the Focus and Log add-task overlay bars.
struct AIBreakdownButton: View {
    let isEnabled: Bool
    let isGenerating: Bool
    let hasGenerated: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Image(systemName: hasGenerated ? "arrow.clockwise" : "sparkles")
                        .font(.sf(.body, weight: .semibold))
                }
                Text(LocalizedStringKey(hasGenerated ? "Regenerate" : "Break Down task"))
                    .font(.sf(.subheadline, weight: .medium))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isEnabled {
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.commitGradientDark,
                                    Color.commitGradientLight,
                                    Color.commitGradientDark,
                                ],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .blur(radius: 6)
                }
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.5), lineWidth: 1.5)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isGenerating)
    }
}
