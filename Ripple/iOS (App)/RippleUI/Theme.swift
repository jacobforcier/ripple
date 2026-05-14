//
//  Theme.swift
//  Ripple (iOS)
//
//  Brand colors and shared view styling, matched to sharewithripple.com.
//

import SwiftUI

enum RippleTheme {
    static let bg       = Color(red: 7/255,   green: 7/255,   blue: 15/255)
    static let surface  = Color.white.opacity(0.05)
    static let border   = Color.white.opacity(0.10)
    static let accent   = Color(red: 91/255,  green: 138/255, blue: 245/255)
    static let accent2  = Color(red: 56/255,  green: 189/255, blue: 248/255)
    static let text     = Color(red: 238/255, green: 238/255, blue: 255/255)
    static let muted    = Color(red: 120/255, green: 120/255, blue: 160/255)
    static let positive = Color(red: 52/255,  green: 211/255, blue: 153/255)

    static let gradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Standard surface card — translucent fill, hairline border, rounded.
struct RippleCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(RippleTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RippleTheme.border, lineWidth: 1)
            )
            .cornerRadius(14)
    }
}

extension View {
    func rippleCard() -> some View { modifier(RippleCard()) }

    /// Fills the background with the brand near-black, ignoring safe areas.
    func rippleBackground() -> some View {
        background(RippleTheme.bg.ignoresSafeArea())
    }
}
