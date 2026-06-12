//
//  RootView.swift
//  Ripple (iOS)
//
//  The app's tab bar. SceneDelegate hosts this view.
//

import SwiftUI

struct RootView: View {

    // Talks to the real backend. Launch with the -mockAPI argument (simulator
    // tooling / UI iteration) to swap in sample data — nothing else changes.
    @StateObject private var store = RippleStore(
        api: ProcessInfo.processInfo.arguments.contains("-mockAPI")
            ? MockRippleAPI() : LiveRippleAPI()
    )
    @StateObject private var celebrator = ProgressionCelebrator()

    init() {
        Self.configureAppearance()
    }

    // Dev affordance: `-startTab 2` opens on a given tab (simulator tooling).
    @State private var selectedTab: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count,
           let n = Int(args[i + 1]) { return n }
        return 0
    }()

    var body: some View {
        TabView(selection: $selectedTab) {
            LinksView()
                .tabItem { Label("Links", systemImage: "link") }
                .tag(0)

            ShareView()
                .tabItem { Label("Share", systemImage: "square.and.arrow.up") }
                .tag(1)

            JourneyView()
                .tabItem { Label("Journey", systemImage: "water.waves") }
                .tag(2)

            RatesView()
                .tabItem { Label("Rates", systemImage: "percent") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(RippleTheme.accent)
        .environmentObject(store)
        // Celebrations fire at the root so they show on any tab.
        .onChange(of: store.milestones) { payload in
            celebrator.process(payload)
        }
        .overlay {
            if let celebration = celebrator.current {
                CelebrationOverlay(celebration: celebration) {
                    celebrator.dismiss()
                }
            }
        }
    }

    /// Dark, brand-colored nav bars and tab bar across the app.
    private static func configureAppearance() {
        let bg = UIColor(RippleTheme.bg)

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = bg
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = bg
        navBar.titleTextAttributes = [.foregroundColor: UIColor(RippleTheme.text)]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor(RippleTheme.text)]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
    }
}

// MARK: - Shared small views

/// The gradient "ripple" wordmark used in nav bars.
struct RippleWordmark: View {
    var body: some View {
        Text("ripple")
            .font(.system(size: 20, weight: .bold))
            .overlay(RippleTheme.gradient)
            .mask(
                Text("ripple")
                    .font(.system(size: 20, weight: .bold))
            )
    }
}

/// A simple loading row.
struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView().tint(RippleTheme.accent)
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

/// A centered empty / error state with an icon and message.
struct MessageState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(RippleTheme.muted)
            Text(title)
                .font(.headline)
                .foregroundColor(RippleTheme.text)
            Text(message)
                .font(.subheadline)
                .foregroundColor(RippleTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}
