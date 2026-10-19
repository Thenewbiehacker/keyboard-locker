import SwiftUI
import Combine

final class HoldTimerModel: ObservableObject {
    @Published var progress: CGFloat = 0

    private var timer: Timer?
    private var startedAt: TimeInterval?
    private var duration: TimeInterval = 3
    private var completion: (() -> Void)?

    var isHolding: Bool { startedAt != nil }

    func begin(duration: TimeInterval, completion: @escaping () -> Void) {
        guard startedAt == nil else { return }
        self.duration = duration
        self.completion = completion
        startedAt = ProcessInfo.processInfo.systemUptime
        progress = 0

        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        startedAt = nil
        completion = nil
        timer?.invalidate()
        timer = nil
        progress = 0
    }

    private func tick() {
        guard let start = startedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let value = CGFloat(min(1, elapsed / duration))
        progress = value
        if value >= 1 {
            let action = completion
            cancel()
            action?()
        }
    }
}

/// A capsule you have to press and keep pressed. Used as the mouse-only
/// emergency unlock, so a single stray click cannot unlock the keyboard.
struct HoldToActivate: View {
    let title: String
    let holdDuration: TimeInterval
    let action: () -> Void

    @StateObject private var holder = HoldTimerModel()

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.06))
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: geometry.size.width * holder.progress)
            }
            .clipShape(Capsule())

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(holder.isHolding ? 0.95 : 0.55))
                .monospacedDigit()
        }
        .frame(width: 300, height: 38)
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !holder.isHolding {
                        holder.begin(duration: holdDuration, completion: action)
                    }
                }
                .onEnded { _ in
                    holder.cancel()
                }
        )
        .onDisappear { holder.cancel() }
        .accessibilityLabel(title)
    }

    private var label: String {
        guard holder.isHolding else { return title }
        let remaining = max(0, holdDuration * Double(1 - holder.progress))
        return "Keep holding… \(String(format: "%.1f", remaining))s"
    }
}
