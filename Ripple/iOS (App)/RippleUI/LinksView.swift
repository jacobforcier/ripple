//
//  LinksView.swift
//  Ripple (iOS)
//
//  Home tab: earnings summary + the history of links you've shared.
//

import SwiftUI

struct LinksView: View {
    @EnvironmentObject private var store: RippleStore

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    EarningsHeader(earnings: store.earnings)

                    if store.isLoading && !store.hasLoadedOnce {
                        LoadingRow()
                    } else if let error = store.loadError {
                        MessageState(
                            systemImage: "exclamationmark.triangle",
                            title: "Couldn't load your links",
                            message: error
                        )
                    } else if store.links.isEmpty {
                        MessageState(
                            systemImage: "link",
                            title: "No links yet",
                            message: "Share a product with the Ripple extension or the Share tab — it'll show up here."
                        )
                    } else {
                        HStack {
                            Text("Your links")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(RippleTheme.muted)
                            Spacer()
                        }
                        .padding(.top, 4)

                        ForEach(store.links) { link in
                            LinkRow(link: link)
                        }
                    }
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Links")
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
}

// MARK: - Earnings header

private struct EarningsHeader: View {
    let earnings: EarningsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lifetime earnings")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(RippleTheme.muted)
                    .textCase(.uppercase)
                Text(formatCents(earnings.lifetimeCents))
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(RippleTheme.text)
            }

            Divider().background(RippleTheme.border)

            HStack(spacing: 12) {
                EarningsStat(
                    label: "Pending",
                    amount: earnings.pendingCents,
                    tint: RippleTheme.accent2
                )
                EarningsStat(
                    label: "Confirmed",
                    amount: earnings.confirmedCents,
                    tint: RippleTheme.positive
                )
                EarningsStat(
                    label: "Paid out",
                    amount: earnings.paidCents,
                    tint: RippleTheme.muted
                )
            }

            Text("Pending earnings clear after the retailer's return window — usually around 90 days.")
                .font(.caption)
                .foregroundColor(RippleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }
}

private struct EarningsStat: View {
    let label: String
    let amount: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(RippleTheme.muted)
            Text(formatCents(amount))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Link row

private struct LinkRow: View {
    let link: RippleLink
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.retailer ?? link.sourceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(RippleTheme.text)
                    Text(link.sourceURL)
                        .font(.caption)
                        .foregroundColor(RippleTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(formatCents(link.earnedCents))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(link.earnedCents > 0 ? RippleTheme.positive : RippleTheme.muted)
            }

            HStack(spacing: 14) {
                Label("\(link.clickCount)", systemImage: "cursorarrow.click")
                if link.pendingCents > 0 {
                    Label(formatCents(link.pendingCents), systemImage: "clock")
                        .foregroundColor(RippleTheme.accent2)
                }
                Spacer()
                Text(relativeDate(link.createdAt))
            }
            .font(.caption)
            .foregroundColor(RippleTheme.muted)

            Button {
                UIPasteboard.general.string = link.rippleURL
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : link.rippleURL.replacingOccurrences(of: "https://", with: ""))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.weight(.medium))
                .foregroundColor(copied ? RippleTheme.positive : RippleTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RippleTheme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(RippleTheme.border, lineWidth: 1)
                )
                .cornerRadius(9)
            }
            .buttonStyle(.plain)
        }
        .rippleCard()
    }
}
