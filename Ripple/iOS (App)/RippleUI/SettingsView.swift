//
//  SettingsView.swift
//  Ripple (iOS)
//
//  Settings tab: Safari extension status/instructions, plus about + links.
//

import SwiftUI

struct SettingsView: View {

    private let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    extensionCard
                    aboutCard
                    legalCard
                    footnote
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .principal) { RippleWordmark() }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Cards

    private var extensionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("How to share")

            Text("On any product page — in Safari, the Amazon app, anywhere — tap the Share button and choose Ripple. You'll get a shareable link to send a friend. It only acts when you tap it.")
                .font(.subheadline)
                .foregroundColor(RippleTheme.muted)

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Find a product you'd recommend")
                instructionRow(number: "2", text: "Tap the Share button, then choose Ripple")
                instructionRow(number: "3", text: "Send your Ripple link to a friend")
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("About")
            Text("Ripple turns the product links you already share into a small commission — no influencer account, no extra steps. Every Ripple link shows a clear disclosure to whoever clicks it.")
                .font(.subheadline)
                .foregroundColor(RippleTheme.muted)
            HStack {
                Text("Version")
                    .font(.subheadline)
                    .foregroundColor(RippleTheme.text)
                Spacer()
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(RippleTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }

    private var legalCard: some View {
        VStack(spacing: 0) {
            linkRow(title: "Visit sharewithripple.com",
                    url: "https://sharewithripple.com")
            Divider().background(RippleTheme.border)
            linkRow(title: "Privacy Policy",
                    url: "https://sharewithripple.com/privacy")
        }
        .rippleCard()
    }

    private var footnote: some View {
        Text("© 2026 Ripple")
            .font(.caption)
            .foregroundColor(RippleTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundColor(RippleTheme.accent)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(RippleTheme.gradient)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(RippleTheme.text)
            Spacer()
        }
    }

    private func linkRow(title: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) {
                UIApplication.shared.open(link)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(RippleTheme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(RippleTheme.muted)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
