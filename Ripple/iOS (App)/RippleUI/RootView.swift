//
//  RootView.swift
//  Ripple (iOS)
//
//  The app's tab bar. SceneDelegate hosts this view.
//

import SwiftUI

struct RootView: View {

    // SWAP POINT: replace MockRippleAPI() with LiveRippleAPI(...) once the
    // backend is deployed. Nothing else in the app needs to change.
    @StateObject private var store = RippleStore(api: MockRippleAPI())

    init() {
        Self.configureAppearance()
    }

    var body: some View {
        TabView {
            LinksView()
                .tabItem { Label("Links", systemImage: "link") }

            ShareView()
                .tabItem { Label("Share", systemImage: "square.and.arrow.up") }

            TrendingView()
                .tabItem { Label("Trending", systemImage: "chart.line.uptrend.xyaxis") }

            RatesView()
                .tabItem { Label("Rates", systemImage: "percent") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(RippleTheme.accent)
        .environmentObject(store)
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
