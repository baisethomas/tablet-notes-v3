import SwiftUI
import UserNotifications

// TAB-119: the two places the user meets scripture reminders. Both take the
// scheduler as a plain property: it is `@Observable`, so reading `isEnabled`
// and `authorizationStatus` in the body is enough to track them.

/// One-time card in the summary tab after the first summary completes. Asking
/// here, with the sermon in view, is the in-context permission prompt the plan
/// calls for; the system prompt appears only when the user taps Turn On.
struct ScriptureReminderOptInCard: View {
    let scheduler: any ScriptureReminderScheduling
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.SV.primary)
                Text("Get this week's scriptures as reminders?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.SV.onSurface)
            }

            Text("A short reminder each morning this week with a scripture from this sermon and one line from your summary. Every new sermon is included once you turn it on.")
                .font(.system(size: 13))
                .foregroundStyle(Color.SV.onSurface.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    scheduler.markOptInPromptSeen()
                } label: {
                    Text("Not Now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)

                Button {
                    guard !isRequesting else { return }
                    isRequesting = true
                    Task {
                        _ = await scheduler.requestAuthorizationAndEnable()
                        isRequesting = false
                    }
                } label: {
                    Text(isRequesting ? "Turning On…" : "Turn On")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.SV.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
            }
        }
        .padding(16)
        .background(Color.SV.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

/// Settings row. A toggle while the system permission allows it; once the
/// user has denied notifications, an explanation and a link to the system
/// Settings app instead of a switch that could never turn on.
struct ScriptureReminderSettingRow: View {
    let scheduler: any ScriptureReminderScheduling
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOn = false
    @State private var isUpdating = false

    private var isDenied: Bool {
        scheduler.authorizationStatus == .denied
    }

    var body: some View {
        Group {
            if isDenied {
                SettingsRow(
                    icon: "bell.slash",
                    title: "Scripture Reminders",
                    subtitle: "Notifications are off for TabletNotes. Allow them in Settings to get this week's scriptures."
                ) {
                    Button("Open Settings") {
                        openSystemNotificationSettings()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.SV.primary)
                }
            } else {
                SettingsToggle(
                    icon: "bell.badge",
                    title: "Scripture Reminders",
                    subtitle: "A scripture from your latest sermon, four mornings a week",
                    isOn: $isOn
                )
                .disabled(isUpdating)
            }
        }
        .task {
            isOn = scheduler.isEnabled
            await scheduler.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have changed the permission in the Settings app.
            guard phase == .active else { return }
            Task { await scheduler.refreshAuthorizationStatus() }
        }
        .onChange(of: scheduler.isEnabled) { _, enabled in
            isOn = enabled
        }
        .onChange(of: isOn) { _, wantsOn in
            guard !isUpdating, wantsOn != scheduler.isEnabled else { return }
            isUpdating = true
            Task {
                if wantsOn {
                    _ = await scheduler.requestAuthorizationAndEnable()
                } else {
                    await scheduler.setEnabled(false)
                }
                // A denied request leaves the feature off; snap the switch back.
                isOn = scheduler.isEnabled
                isUpdating = false
            }
        }
    }

    private func openSystemNotificationSettings() {
        let urlString: String
        if #available(iOS 16.0, *) {
            urlString = UIApplication.openNotificationSettingsURLString
        } else {
            urlString = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
