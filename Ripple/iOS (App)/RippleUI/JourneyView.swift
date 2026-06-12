//
//  JourneyView.swift
//  Ripple (iOS)
//
//  The Journey tab: an animated liquid-wave tier header (the water level IS
//  your progress to the next tier) + the milestone path — a winding trail of
//  nodes you climb, game-map style. Replaces the flat checklist.
//

import SwiftUI
import UIKit

struct JourneyView: View {
    @EnvironmentObject private var store: RippleStore

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    WaveTierHeader(progress: store.milestones.tier)
                    MilestonePath(milestones: store.milestones.milestones)
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Journey")
            .toolbar { ToolbarItem(placement: .principal) { RippleWordmark() } }
            .refreshable { await store.loadAll() }
        }
        .navigationViewStyle(.stack)
        .task {
            if !store.hasLoadedOnce { await store.loadAll() }
        }
    }
}

// MARK: - Liquid wave tier header

struct WaveTierHeader: View {
    let progress: TierProgress
    @State private var showShare = false

    /// 0…1 progress within the current rung. Floor keeps the water visible
    /// and alive even at $0 — the feature should never look "empty".
    private var rungFraction: CGFloat {
        guard let next = progress.next else { return 0.92 }
        let total = progress.lifetimeConfirmedCents + next.remainingCents
        guard total > 0 else { return 0.18 }
        return min(0.92, max(0.18, CGFloat(progress.lifetimeConfirmedCents) / CGFloat(total)))
    }

    private var percentToNext: Int {
        guard let next = progress.next else { return 100 }
        let total = progress.lifetimeConfirmedCents + next.remainingCents
        guard total > 0 else { return 0 }
        return Int((Double(progress.lifetimeConfirmedCents) / Double(total)) * 100)
    }

    private var nextLine: String {
        guard let next = progress.next else { return "Top of the ladder — maximum bonus on every ripple." }
        return "\(formatCents(next.remainingCents)) more confirmed → \(next.tier) (+\(next.bonusPoints)% bonus)"
    }

    /// Builds one sine wave surface as a closed path. Typed simply so the
    /// SwiftUI type-checker stays fast (this used to live inline in Canvas).
    private func wavePath(size: CGSize, level: CGFloat, time: Double,
                          freq: Double, speed: Double, amp: CGFloat,
                          freq2: Double = 0, speed2: Double = 0, amp2: CGFloat = 0,
                          phase: Double = 0) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: level))
        var x: CGFloat = 0
        while x <= size.width {
            let u = Double(x / size.width)
            var y = level + amp * CGFloat(sin(u * .pi * freq + time * speed + phase))
            if amp2 > 0 {
                y += amp2 * CGFloat(sin(u * .pi * freq2 + time * speed2))
            }
            p.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()
        return p
    }

    private func drawWater(context: GraphicsContext, size: CGSize, time: Double) {
        // Level comes straight from real progress every frame (no animation
        // state to go stale), with a slow breathing bob so it's always alive.
        let bob = CGFloat(sin(time * 0.6)) * 4
        let level: CGFloat = (1 - rungFraction) * size.height + bob

        let back = wavePath(size: size, level: level, time: time,
                            freq: 2, speed: 1.1, amp: 13, phase: 1.8)
        let front = wavePath(size: size, level: level, time: time,
                             freq: 2, speed: 1.7, amp: 10,
                             freq2: 5, speed2: 2.6, amp2: 5)

        context.fill(back, with: .color(RippleTheme.accent.opacity(0.28)))
        context.fill(front, with: .linearGradient(
            Gradient(colors: [RippleTheme.accent2.opacity(0.85),
                              RippleTheme.accent.opacity(0.45)]),
            startPoint: CGPoint(x: 0, y: level),
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        // Glowing crest line along the front wave surface.
        var crest = Path()
        var x: CGFloat = 0
        var first = true
        while x <= size.width {
            let u = Double(x / size.width)
            var y = level + 10 * CGFloat(sin(u * .pi * 2 + time * 1.7))
            y += 5 * CGFloat(sin(u * .pi * 5 + time * 2.6))
            if first { crest.move(to: CGPoint(x: x, y: y)); first = false }
            else { crest.addLine(to: CGPoint(x: x, y: y)) }
            x += 4
        }
        context.stroke(crest, with: .color(RippleTheme.accent2.opacity(0.9)), lineWidth: 2)

        // Bubbles drifting up through the water.
        for i in 0..<6 {
            let seed = Double(i) * 1.7 + 1
            let cycle = 6.0 + Double(i % 3)
            let phase = (time / cycle + seed * 0.37).truncatingRemainder(dividingBy: 1)
            let bx = CGFloat((seed * 137.5).truncatingRemainder(dividingBy: 1)) * size.width * 0.9
                   + size.width * 0.05
                   + CGFloat(sin(time * 1.2 + seed)) * 6
            let depth = size.height - level
            guard depth > 24 else { continue }
            let by = size.height - CGFloat(phase) * (depth - 14)
            let r = 2.0 + CGFloat(i % 3)
            let alpha = 0.5 * (1 - phase)
            context.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(alpha)))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Animated water, clipped to the card. Level = rung progress.
                TimelineView(.animation) { timeline in
                    let t: Double = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        drawWater(context: context, size: size, time: t)
                    }
                }

                // Soft glow halo behind the tier name.
                RadialGradient(
                    colors: [RippleTheme.accent.opacity(0.35), .clear],
                    center: .center, startRadius: 10, endRadius: 150
                )
                .frame(width: 300, height: 220)
                .offset(y: -20)

                VStack(spacing: 6) {
                    Text("YOUR TIER")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(RippleTheme.muted)
                        .tracking(1.4)
                    Text(progress.tier)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(RippleTheme.text)
                        .shadow(color: .black.opacity(0.45), radius: 8)
                    Text(progress.bonusPoints > 0
                         ? "+\(progress.bonusPoints)% bonus on every ripple"
                         : "base rate — your first sale starts the climb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(RippleTheme.text.opacity(0.92))
                        .shadow(color: .black.opacity(0.45), radius: 6)
                    Text(nextLine)
                        .font(.caption)
                        .foregroundColor(RippleTheme.text.opacity(0.75))
                        .shadow(color: .black.opacity(0.4), radius: 5)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .offset(y: -16)

                // Progress chip riding the lower-right, above the water.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(progress.next == nil ? "MAX" : "\(percentToNext)% to \(progress.next!.tier)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                            .overlay(Capsule().stroke(RippleTheme.accent2.opacity(0.5), lineWidth: 1))
                            .padding(12)
                    }
                }
            }
            .frame(height: 250)

            // Ladder rungs + share
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(i <= progress.ladderIndex
                                  ? AnyShapeStyle(RippleTheme.gradient)
                                  : AnyShapeStyle(RippleTheme.border))
                            .frame(width: 26, height: 5)
                    }
                }
                Spacer()
                if progress.ladderIndex > 0 {
                    Button { showShare = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(RippleTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RippleTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RippleTheme.border, lineWidth: 1)
        )
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [
                "I just became a \(progress.tier) on Ripple 🌊 — my recommendations are paying me back. sharewithripple.com"
            ])
        }
    }
}

// MARK: - Milestone path (the game map)

struct MilestonePath: View {
    let milestones: [Milestone]
    private let rowHeight: CGFloat = 96

    private var icon: [String: String] {
        ["first_link": "link",
         "first_click": "hand.tap",
         "three_retailers": "bag",
         "ten_clicks": "flame",
         "first_group": "person.3",
         "first_earnings": "dollarsign.circle",
         "first_confirmed": "checkmark.seal",
         "first_payout": "banknote"]
    }

    /// The first unachieved milestone pulses as "you are here".
    private var nextID: String? {
        milestones.first(where: { !$0.achieved })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE PATH")
                .font(.caption2.weight(.bold))
                .foregroundColor(RippleTheme.muted)
                .tracking(1.4)
                .padding(.bottom, 8)

            ZStack(alignment: .top) {
                // Winding connector behind the nodes
                GeometryReader { geo in
                    Path { p in
                        let w = geo.size.width
                        for i in 0..<max(0, milestones.count - 1) {
                            let from = nodeCenter(i, width: w)
                            let to = nodeCenter(i + 1, width: w)
                            p.move(to: from)
                            p.addCurve(
                                to: to,
                                control1: CGPoint(x: from.x, y: from.y + rowHeight * 0.55),
                                control2: CGPoint(x: to.x, y: to.y - rowHeight * 0.55)
                            )
                        }
                    }
                    .stroke(RippleTheme.border,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9]))
                }

                VStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.element.id) { index, m in
                        MilestoneNode(
                            milestone: m,
                            symbol: icon[m.id] ?? "circle",
                            isNext: m.id == nextID,
                            alignLeft: index % 2 == 0
                        )
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }

    private func nodeCenter(_ index: Int, width: CGFloat) -> CGPoint {
        let x = index % 2 == 0 ? width * 0.18 : width * 0.82
        return CGPoint(x: x, y: CGFloat(index) * rowHeight + rowHeight / 2)
    }
}

private struct MilestoneNode: View {
    let milestone: Milestone
    let symbol: String
    let isNext: Bool
    let alignLeft: Bool

    @State private var pulse = false
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 14) {
            if !alignLeft { textBlock(trailing: true); Spacer(minLength: 0) }

            ZStack {
                if isNext {
                    Circle()
                        .stroke(RippleTheme.accent.opacity(0.5), lineWidth: 2)
                        .frame(width: 66, height: 66)
                        .scaleEffect(pulse ? 1.25 : 0.95)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false),
                                   value: pulse)
                }
                Circle()
                    .fill(milestone.achieved
                          ? AnyShapeStyle(RippleTheme.gradient)
                          : AnyShapeStyle(RippleTheme.surface))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle().stroke(
                            milestone.achieved ? Color.clear :
                                (isNext ? RippleTheme.accent : RippleTheme.border),
                            lineWidth: 1.5)
                    )
                    .shadow(color: milestone.achieved
                            ? RippleTheme.accent.opacity(0.45) : .clear,
                            radius: 10)
                Image(systemName: milestone.achieved ? "checkmark" : symbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(milestone.achieved ? .white :
                                     (isNext ? RippleTheme.accent : RippleTheme.muted))
            }
            .scaleEffect(pressed ? 1.18 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pressed)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pressed = false }
            }
            .onAppear { if isNext { pulse = true } }

            if alignLeft { Spacer(minLength: 0); textBlock(trailing: false) }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func textBlock(trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(milestone.title)
                .font(.subheadline.weight(milestone.achieved || isNext ? .semibold : .regular))
                .foregroundColor(milestone.achieved || isNext ? RippleTheme.text : RippleTheme.muted)
                .multilineTextAlignment(trailing ? .trailing : .leading)
            Text(milestone.detail)
                .font(.caption2)
                .foregroundColor(isNext ? RippleTheme.accent : RippleTheme.muted.opacity(0.8))
                .multilineTextAlignment(trailing ? .trailing : .leading)
        }
        .frame(maxWidth: 200, alignment: trailing ? .trailing : .leading)
    }
}
