//
//  NotificationToggleRow.swift
//  Focus IOS
//

import SwiftUI

struct NotificationToggleRow: View {
    @Binding var isEnabled: Bool
    @Binding var selectedTime: Date
    @Binding var isExpanded: Bool
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasAppeared = false
    @State private var showPermissionAlert = false
    /// Tracks that the user wanted to enable this reminder but was sent to Settings first
    @State private var pendingReminderEnable = false

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: selectedTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, AppStyle.Spacing.content)

            // Single row: bell + label/time + toggle
            HStack {
                // Tappable left side to expand/collapse
                Button {
                    if isEnabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .frame(width: 24)

                        if isEnabled {
                            Text(formattedTime)
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.focusBlue)
                        } else {
                            Text("Reminder")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.primary)
                        }

                        if isEnabled {
                            Image(systemName: "chevron.down")
                                .font(.inter(.caption2))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            if notificationManager.isEnabled {
                                isEnabled = true
                            } else {
                                showPermissionAlert = true
                            }
                        } else {
                            isEnabled = false
                        }
                    }
                ))
                .labelsHidden()
                .tint(.focusBlue)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.vertical, AppStyle.Spacing.comfortable)

            if isEnabled && isExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                TimeWheelPicker(selection: $selectedTime, minuteInterval: 5)
                    .frame(height: 200)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .id("notificationTimePicker")
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            guard hasAppeared else { return }
            if enabled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
        }
        .alert("Notifications are off", isPresented: $showPermissionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Enable Notifications") {
                pendingReminderEnable = true
                _Concurrency.Task { @MainActor in
                    let enabled = await notificationManager.enableNotifications()
                    if enabled {
                        pendingReminderEnable = false
                        isEnabled = true
                    }
                }
            }
        } message: {
            Text("Enable notifications to set reminders for your tasks.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                notificationManager.checkSystemAuthorization()
            }
        }
        .onChange(of: notificationManager.isEnabled) { _, nowEnabled in
            if nowEnabled && pendingReminderEnable {
                pendingReminderEnable = false
                isEnabled = true
            }
        }
    }
}

// MARK: - UIKit Time Wheel Picker with minute interval

private struct TimeWheelPicker: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = minuteInterval
        picker.date = selection
        picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        picker.date = selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        let selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func dateChanged(_ picker: UIDatePicker) {
            selection.wrappedValue = picker.date
        }
    }
}
