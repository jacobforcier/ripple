//
//  RatesView.swift
//  Ripple (iOS)
//
//  Rates tab: a searchable reference of typical commission rates by retailer.
//

import SwiftUI

struct RatesView: View {
    @EnvironmentObject private var store: RippleStore
    @State private var query = ""

    private var filtered: [RetailerRate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.rates }
        return store.rates.filter {
            $0.retailer.localizedCaseInsensitiveContains(trimmed) ||
            $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What retailers typically pay")
                            .font(.headline)
                            .foregroundColor(RippleTheme.text)
                        Text("Approximate commission rates by retailer and category. Actual rates vary and change over time — treat these as a rough guide.")
                            .font(.subheadline)
                            .foregroundColor(RippleTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rippleCard()

                    if filtered.isEmpty {
                        MessageState(
                            systemImage: "magnifyingglass",
                            title: "No matches",
                            message: "No retailers match \"\(query)\"."
                        )
                    } else {
                        ForEach(filtered) { rate in
                            RateRow(rate: rate)
                        }
                    }
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Rates")
            .toolbar {
                ToolbarItem(placement: .principal) { RippleWordmark() }
            }
        }
        .navigationViewStyle(.stack)
        .searchable(text: $query, prompt: "Search retailers")
    }
}

private struct RateRow: View {
    let rate: RetailerRate

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rate.retailer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(RippleTheme.text)
                Text(rate.category)
                    .font(.caption)
                    .foregroundColor(RippleTheme.muted)
            }
            Spacer()
            Text(rate.rateText)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(RippleTheme.accent2)
        }
        .rippleCard()
    }
}
