//
//  ProgressionView.swift
//  Ripple (iOS)
//
//  The tier ladder (Drop → Ripple → Wave → Tide) + milestone checklist, and
//  the celebration layer. Design rule: celebrate actions/clicks (instant),
//  reward earnings with tiers. Tiers never decay; celebrations fire once.
//

import SwiftUI
import UIKit

// MARK: - Tier card

struct TierCard: View {
    let progress: TierProgress
    @State private var animateBar = false
    @State private var showShare = false

    private var nextLine: String {
        guard let next = progress.next else { return "Top of the ladder — every link earns the most." }
        return "\(formatCents(next.remainingCents)) more confirmed → \(next.tier) (\(Int(next.rate * 100))%)"
    }

    /// Progress within the current rung, for the bar (0…1).
    private var rungFraction: CGFloat {
        guard let next = progress.next else { return 1 }
        let total = progress.lifetimeConfirmedCents + next.remainingCents
        guard total > 0 else { return 0 }
        return CGFloat(progress.lifetimeConfirmedCents) / CGFloat(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                ZStack {
                    Circle()
                        .fill(RippleTheme.gradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: RippleTheme.accent.opacity(0.5), radius: 10)
                    Image(systemName: progress.ladderIndex == 0 ? "drop.fill" : "water.waves")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR TIER")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(RippleTheme.muted)
                        .tracking(1.2)
                    Text(progress.tier)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(RippleTheme.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("you earn")
                        .font(.caption2)
                        .foregroundColor(RippleTheme.muted)
                    Text("\(Int(progress.rate * 100))%")
                        .font(.system(size: 26, weight: .bold))
                        .overlay(RippleTheme.gradient.mask(
                            Text("\(Int(progress.rate * 100))%")
                                .font(.system(size: 26, weight: .bold))
                        ))
                }
            }

            // Ladder dots + progress bar to the next rung
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(i <= progress.ladderIndex
                                  ? AnyShapeStyle(RippleTheme.gradient)
                                  : AnyShapeStyle(RippleTheme.border))
                            .frame(height: 5)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(RippleTheme.border).frame(height: 8)
                        Capsule()
                            .fill(RippleTheme.gradient)
                            .frame(width: max(8, geo.size.width * (animateBar ? rungFraction : 0)),
                                   height: 8)
                            .animation(.easeOut(duration: 0.9), value: animateBar)
                    }
                }
                .frame(height: 8)
                Text(nextLine)
                    .font(.caption)
                    .foregroundColor(RippleTheme.muted)
            }

            if progress.ladderIndex > 0 {
                Button {
                    showShare = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share your tier")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(RippleTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
        .onAppear { animateBar = true }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [
                "I just became a \(progress.tier) on Ripple 🌊 — my recommendations are paying me back. sharewithripple.com"
            ])
        }
    }
}

// MARK: - Milestones checklist

struct MilestonesCard: View {
    let milestones: [Milestone]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR PROGRESS")
                .font(.caption2.weight(.bold))
                .foregroundColor(RippleTheme.muted)
                .tracking(1.2)
                .padding(.bottom, 6)

            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, m in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .strokeBorder(m.achieved ? Color.clear : RippleTheme.border, lineWidth: 1.5)
                            .background(
                                Circle().fill(m.achieved
                                              ? AnyShapeStyle(RippleTheme.gradient)
                                              : AnyShapeStyle(Color.clear))
                            )
                            .frame(width: 26, height: 26)
                        if m.achieved {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title)
                            .font(.subheadline.weight(m.achieved ? .semibold : .regular))
                            .foregroundColor(m.achieved ? RippleTheme.text : RippleTheme.muted)
                        Text(m.detail)
                            .font(.caption2)
                            .foregroundColor(RippleTheme.muted.opacity(0.8))
                    }
                    Spacer()
                }
                .padding(.vertical, 7)
                if index < milestones.count - 1 {
                    Divider().background(RippleTheme.border)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }
}

// MARK: - Celebrations

/// Watches milestone payloads and fires each celebration exactly once per
/// device (achieved ids + last tier persisted in UserDefaults). One at a time.
@MainActor
final class ProgressionCelebrator: ObservableObject {
    @Published var current: Celebration?

    struct Celebration: Equatable {
        let title: String
        let subtitle: String
        let isTierUp: Bool
    }

    private let defaults = UserDefaults.standard
    private let seenKey = "ripple.milestones.seen"
    private let tierKey = "ripple.tier.lastSeen"
    private var queue: [Celebration] = []

    func process(_ payload: MilestonesResponse) {
        guard payload != .empty else { return }
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let lastTier = defaults.integer(forKey: tierKey)

        // First run: baseline silently so long-time state doesn't replay.
        let isFirstRun = !defaults.bool(forKey: "ripple.progression.baselined")
        defer {
            defaults.set(Array(seen), forKey: seenKey)
            defaults.set(payload.tier.ladderIndex, forKey: tierKey)
            defaults.set(true, forKey: "ripple.progression.baselined")
        }

        for m in payload.milestones where m.achieved && !seen.contains(m.id) {
            seen.insert(m.id)
            if !isFirstRun {
                queue.append(Celebration(title: m.title, subtitle: m.detail, isTierUp: false))
            }
        }
        if payload.tier.ladderIndex > lastTier && !isFirstRun {
            queue.append(Celebration(
                title: "You're a \(payload.tier.tier)!",
                subtitle: "Every link now earns you \(Int(payload.tier.rate * 100))%",
                isTierUp: true
            ))
        }
        showNextIfIdle()
    }

    func dismiss() {
        current = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.showNextIfIdle() }
    }

    private func showNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

/// Full-screen ripple-ring celebration. Tap anywhere to dismiss; auto-dismisses.
struct CelebrationOverlay: View {
    let celebration: ProgressionCelebrator.Celebration
    let onDismiss: () -> Void
    @State private var ringScale: CGFloat = 0.4
    @State private var ringOpacity: Double = 0.9
    @State private var contentScale: CGFloat = 0.85

    var body: some View {
        ZStack {
            RippleTheme.bg.opacity(0.85).ignoresSafeArea()

            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(RippleTheme.gradient, lineWidth: 3)
                    .frame(width: 180 + CGFloat(i) * 110, height: 180 + CGFloat(i) * 110)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .animation(.easeOut(duration: 1.4).delay(Double(i) * 0.18), value: ringScale)
            }

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(RippleTheme.gradient)
                        .frame(width: 72, height: 72)
                        .shadow(color: RippleTheme.accent.opacity(0.6), radius: 18)
                    Image(systemName: celebration.isTierUp ? "water.waves" : "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(celebration.title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(RippleTheme.text)
                    .multilineTextAlignment(.center)
                Text(celebration.subtitle)
                    .font(.subheadline)
                    .foregroundColor(RippleTheme.muted)
                    .multilineTextAlignment(.center)
                Text("tap to continue")
                    .font(.caption2)
                    .foregroundColor(RippleTheme.muted.opacity(0.6))
                    .padding(.top, 14)
            }
            .padding(32)
            .scaleEffect(contentScale)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: contentScale)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            ringScale = 1.25
            ringOpacity = 0
            contentScale = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { onDismiss() }
        }
        .transition(.opacity)
    }
}

// MARK: - Share sheet (iOS 15-compatible)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
