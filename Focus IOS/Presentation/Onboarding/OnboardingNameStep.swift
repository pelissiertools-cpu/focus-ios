//
//  OnboardingNameStep.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingNameStep: View {
    @EnvironmentObject var authService: AuthService
    let onContinue: () -> Void

    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Avatar circle with initial
            Circle()
                .fill(Color.focusBlue.opacity(0.12))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(nameInitial)
                        .font(.inter(size: 32, weight: .bold))
                        .foregroundColor(.focusBlue)
                )
                .padding(.bottom, AppStyle.Spacing.expanded)

            Text("What's your name?")
                .font(AppStyle.Typography.pageTitle)
                .tracking(AppStyle.Typography.pageTitleTracking)
                .foregroundColor(.appText)
                .padding(.bottom, AppStyle.Spacing.section)

            // Name field
            HStack {
                TextField("Your name", text: $name)
                    .font(.inter(.title3))
                    .focused($nameFieldFocused)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .onSubmit { saveName() }

                if !name.isEmpty {
                    Button {
                        name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(AppStyle.Spacing.content)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                    .stroke(
                        nameFieldFocused ? Color.focusBlue : Color.cardBorder,
                        lineWidth: nameFieldFocused ? AppStyle.Border.focused : AppStyle.Border.standard
                    )
            )
            .padding(.horizontal, AppStyle.Spacing.page)

            // Error
            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.inter(.caption))
                    .padding(.top, AppStyle.Spacing.small)
            }

            Spacer()
            Spacer()

            Button(action: saveName) {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.focusBlue)
                    } else {
                        Text("Next")
                            .font(.helveticaNeue(size: 15.22, weight: .medium))
                            .tracking(-0.158)
                    }
                }
                .foregroundColor(trimmedName.isEmpty ? .secondary : .focusBlue)
                .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                .contentShape(Rectangle())
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                .cardBorderOverlay()
                .cardShadow()
            }
            .buttonStyle(.plain)
            .disabled(trimmedName.isEmpty || authService.isLoading)
            .opacity(trimmedName.isEmpty ? 0.5 : 1)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, AppStyle.Spacing.page)
        .onAppear {
            if let existing = authService.displayName {
                name = existing
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                nameFieldFocused = true
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameInitial: String {
        guard let first = trimmedName.first else { return "?" }
        return String(first).uppercased()
    }

    private func saveName() {
        guard !trimmedName.isEmpty else { return }
        _Concurrency.Task { @MainActor in
            do {
                try await authService.updateDisplayName(trimmedName)
                onContinue()
            } catch {
                // Error message available via authService.errorMessage
            }
        }
    }
}
