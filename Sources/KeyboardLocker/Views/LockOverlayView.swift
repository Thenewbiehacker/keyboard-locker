import SwiftUI
import Combine

enum OverlayMode {
    case countdown
    case locked
    case unlocked
}

final class OverlayModel: ObservableObject {
    @Published var mode: OverlayMode = .countdown
    @Published var progress: Double = 0
    @Published var countdown: Int = 3
    @Published var holdSeconds: Double = 5
    @Published var autoUnlockRemaining: TimeInterval = 0
}

struct LockOverlayView: View {
    @ObservedObject var model: OverlayModel
    let emergencyUnlock: () -> Void

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                switch model.mode {
                case .countdown:
                    countdownContent
                case .locked:
                    lockedContent
                case .unlocked:
                    unlockedContent
                }

                Spacer(minLength: 24)

                if model.mode == .locked {
                    VStack(spacing: 14) {
                        HoldToActivate(
                            title: "Hold here to unlock with the mouse",
                            holdDuration: 3,
                            action: emergencyUnlock
                        )
                        Text("Keyboard unlocks and the app exits automatically as a safety net.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.bottom, 44)
                }
            }
            .padding(.horizontal, 40)
        }
        .ignoresSafeArea()
    }

    // MARK: - Background

    private var backdrop: some View {
        ZStack {
            Color.black.opacity(0.90)
            RadialGradient(
                colors: [
                    Color(red: 0.13, green: 0.17, blue: 0.30).opacity(0.85),
                    Color.black.opacity(0.92)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 820
            )
        }
    }

    // MARK: - Content

    private var countdownContent: some View {
        VStack(spacing: 16) {
            Text("\(model.countdown)")
                .font(.system(size: 132, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .id(model.countdown)
                .transition(.opacity)

            Text("Locking the keyboard…")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Text("Take your hands off the keys. Press Esc to cancel.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 6)
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 24) {
            ring

            VStack(spacing: 10) {
                Text("Keyboard Locked")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                (Text("Hold ") + Text("Space").bold() + Text(" for \(Int(model.holdSeconds)) seconds to unlock"))
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.72))

                Text("Mouse and trackpad still work. The app quits after unlocking.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.top, 4)

                Text("Auto-exits in \(Int(max(0, model.autoUnlockRemaining.rounded(.up)))) s")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }
        }
    }

    private var unlockedContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96, weight: .thin))
                .foregroundStyle(Color.green)
            Text("Keyboard Unlocked")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Closing…")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.0001, model.progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.35, green: 0.95, blue: 0.85),
                            Color(red: 0.30, green: 0.65, blue: 1.0),
                            Color(red: 0.55, green: 0.45, blue: 1.0)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(red: 0.35, green: 0.8, blue: 1.0).opacity(0.35), radius: 12)

            VStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.white)
                if model.progress > 0.01 {
                    Text("\(Int(ceil(model.holdSeconds * (1 - model.progress))))")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 200, height: 200)
        .animation(.linear(duration: 0.07), value: model.progress)
    }
}
