import SwiftUI

struct MainView: View {
    @ObservedObject var controller: LockController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            permissionsCard
            settingsCard

            if let message = controller.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            lockButton

            Text("The keyboard locks after a 3-second countdown. Hold Space to unlock and the app quits by itself. Only the keyboard is blocked — the pointer keeps working.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520, height: 600, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.28, blue: 0.45),
                                Color(red: 0.08, green: 0.10, blue: 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("Keyboard Locker")
                    .font(.system(size: 21, weight: .semibold))
                Text("Clean your keyboard without triggering keys.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        card(title: "Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Accessibility",
                    subtitle: "Lets the app swallow key presses.",
                    granted: controller.accessibilityGranted,
                    openSettings: Permissions.openAccessibilitySettings
                )
                Divider()
                permissionRow(
                    title: "Input Monitoring",
                    subtitle: "Lets the app see the keyboard at all.",
                    granted: controller.inputMonitoringGranted,
                    openSettings: Permissions.openInputMonitoringSettings
                )

                if !controller.permissionsGranted {
                    Button("Request Permissions") {
                        Permissions.requestAll()
                        controller.refreshPermissions()
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(granted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings", action: openSettings)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        card(title: "Unlock & blocking") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hold Space for")
                            .font(.system(size: 13, weight: .medium))
                        Text("How long the space bar must stay down to unlock.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: $controller.holdSeconds, in: 2...10, step: 1) {
                        Text("\(Int(controller.holdSeconds)) s")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                    .fixedSize()
                }

                Divider()

                Toggle(isOn: $controller.blockFnKey) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Block the Fn / Globe key")
                            .font(.system(size: 13, weight: .medium))
                        Text("Also blocks Shift, Command, Option, Control and Caps Lock.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle(isOn: $controller.blockMediaKeys) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Block media & brightness keys")
                            .font(.system(size: 13, weight: .medium))
                        Text("Play/pause, volume and brightness keys are swallowed too.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Lock button

    private var lockButton: some View {
        Button(action: controller.requestLock) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text(controller.phase == .idle ? "Lock Keyboard" : "Locking…")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(controller.phase != .idle)
    }

    // MARK: - Helpers

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
