//
//  TrendingView.swift
//  Ripple (iOS)
//
//  Trending tab: the retailers Ripple users are sharing from most this week.
//

import SwiftUI

struct TrendingView: View {
    @EnvironmentObject private var store: RippleStore

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    header

                    if store.isLoading && !store.hasLoadedOnce {
                        LoadingRow()
                    } else if let error = store.loadError {
                        MessageState(
                            systemImage: "exclamationmark.triangle",
                            title: "Couldn't load trending",
                            message: error
                        )
                    } else if store.trending.isEmpty {
                        MessageState(
                            systemImage: "chart.line.uptrend.xyaxis",
                            title: "Nothing trending yet",
                            message: "Once people start sharing, the most popular retailers will show up here."
                        )
                    } else {
                        ForEach(store.trending) { merchant in
                            TrendingRow(merchant: merchant)
                        }

                        Text("Based on links shared by Ripple users over the last 7 days.")
                            .font(.caption)
                            .foregroundColor(RippleTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Trending")
            .toolbar {
                ToolbarItem(placement: .principal) { RippleWordmark() }
            }
            .refreshable { await store.loadAll() }
        }
        .navigationViewStyle(.stack)
        .task {
            if !store.hasLoadedOnce { await store.loadAll() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What people are sharing")
                .font(.headline)
                .foregroundColor(RippleTheme.text)
            Text("The retailers Ripple users are sending links from most this week. A good nudge for where your recommendations might land.")
                .font(.subheadline)
                .foregroundColor(RippleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }
}

// MARK: - Row

private struct TrendingRow: View {
    let merchant: TrendingMerchant

    var body: some View {
        HStack(spacing: 14) {
            Text("\(merchant.rank)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(RippleTheme.muted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(merchant.retailer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(RippleTheme.text)
                Text("\(merchant.shareCount.formatted()) links shared")
                    .font(.caption)
                    .foregroundColor(RippleTheme.muted)
            }

            Spacer()

            MovementBadge(movement: merchant.movement)
        }
        .rippleCard()
    }
}

private struct MovementBadge: View {
    let movement: TrendMovement

    var body: some View {
        switch movement {
        case .up(let n):
            badge(text: "\(n)", systemImage: "arrow.up", color: RippleTheme.positive)
        case .down(let n):
            badge(text: "\(n)", systemImage: "arrow.down", color: Color(red: 248/255, green: 113/255, blue: 113/255))
        case .new:
            Text("NEW")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RippleTheme.gradient)
                .cornerRadius(6)
        case .steady:
            Image(systemName: "minus")
                .font(.caption.weight(.semibold))
                .foregroundColor(RippleTheme.muted)
        }
    }

    private func badge(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundColor(color)
    }
}
