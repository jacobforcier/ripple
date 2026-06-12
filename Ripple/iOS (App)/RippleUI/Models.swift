//
//  Models.swift
//  Ripple (iOS)
//
//  Data models. CodingKeys mirror the backend's JSON shapes exactly
//  (see backend/src/routes/*.js), so the live API client can decode
//  straight into these once the backend is deployed.
//

import Foundation

// MARK: - Link

/// A Ripple link with its aggregated stats. Mirrors the backend `link_stats`
/// view returned by `GET /v1/links?user_id=`.
struct RippleLink: Identifiable, Codable, Equatable {
    let id: String
    let sourceURL: String
    let retailer: String?
    let createdAt: Date
    let clickCount: Int
    let earnedCents: Int
    let pendingCents: Int
    let confirmedCents: Int
    let paidCents: Int

    enum CodingKeys: String, CodingKey {
        case id, retailer
        case sourceURL      = "source_url"
        case createdAt      = "created_at"
        case clickCount     = "click_count"
        case earnedCents    = "earned_cents"
        case pendingCents   = "pending_cents"
        case confirmedCents = "confirmed_cents"
        case paidCents      = "paid_cents"
    }

    /// The shareable Ripple URL for this link.
    var rippleURL: String { "https://sharewithripple.com/s/\(id)" }

    /// A short, human-friendly version of the source URL (host + first path bit).
    var sourceLabel: String {
        guard let url = URL(string: sourceURL), let host = url.host else { return sourceURL }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Earnings

/// A user's earnings summary. Mirrors `GET /v1/users/:id/earnings`.
/// All amounts are the user's cut (after the platform margin), in cents.
struct EarningsSummary: Codable, Equatable {
    let lifetimeCents: Int
    let pendingCents: Int
    let confirmedCents: Int
    let paidCents: Int

    enum CodingKeys: String, CodingKey {
        case lifetimeCents  = "lifetime_cents"
        case pendingCents   = "pending_cents"
        case confirmedCents = "confirmed_cents"
        case paidCents      = "paid_cents"
    }

    static let zero = EarningsSummary(
        lifetimeCents: 0, pendingCents: 0, confirmedCents: 0, paidCents: 0
    )
}

// MARK: - Created link

/// The result of `POST /v1/links`.
struct CreatedLink: Codable, Equatable {
    let id: String
    let rippleURL: String
    let sourceURL: String
    let retailer: String?

    enum CodingKeys: String, CodingKey {
        case id, retailer
        case rippleURL = "ripple_url"
        case sourceURL = "source_url"
    }
}

// MARK: - Trending

/// A retailer in the trending feed. Mirrors `GET /v1/trending` — the backend
/// returns `rank`, `retailer`, and `share_count`; `movement` is supplied by
/// the mock for now (week-over-week rank deltas need a snapshots table the
/// backend doesn't have yet, so the live path will just show `.steady`).
struct TrendingMerchant: Identifiable, Codable, Equatable {
    let rank: Int
    let retailer: String
    let shareCount: Int
    var movement: TrendMovement = .steady

    var id: String { retailer }

    enum CodingKeys: String, CodingKey {
        case rank, retailer
        case shareCount = "share_count"
    }
}

/// Week-over-week rank movement for a trending merchant.
enum TrendMovement: Equatable {
    case up(Int)
    case down(Int)
    case steady
    case new
}

// MARK: - Retailer rate

/// A typical commission rate for a retailer. Static reference data shown in
/// the Rates tab — actual rates vary by category and change over time.
struct RetailerRate: Identifiable, Equatable {
    let id = UUID()
    let retailer: String
    let category: String
    let rateText: String
}

// MARK: - Tiers & milestones

/// The user's earning tier + progress. Mirrors the `tier` object of
/// `GET /v1/users/:id/milestones`. `rate` is the user's share (0.40…0.55).
struct TierProgress: Codable, Equatable {
    let tier: String
    let rate: Double
    let lifetimeConfirmedCents: Int
    let next: NextTier?

    struct NextTier: Codable, Equatable {
        let tier: String
        let rate: Double
        let remainingCents: Int

        enum CodingKeys: String, CodingKey {
            case tier, rate
            case remainingCents = "remaining_cents"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tier, rate, next
        case lifetimeConfirmedCents = "lifetime_confirmed_cents"
    }

    static let zero = TierProgress(
        tier: "Drop", rate: 0.40, lifetimeConfirmedCents: 0,
        next: NextTier(tier: "Ripple", rate: 0.45, remainingCents: 1)
    )

    /// Ladder position (Drop=0 … Tide=3) for progress visuals.
    var ladderIndex: Int {
        ["Drop": 0, "Ripple": 1, "Wave": 2, "Tide": 3][tier] ?? 0
    }
}

/// One milestone row. Mirrors `milestones[]` of GET /v1/users/:id/milestones.
struct Milestone: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let achieved: Bool
    let detail: String
}

/// Full payload of GET /v1/users/:id/milestones.
struct MilestonesResponse: Codable, Equatable {
    let tier: TierProgress
    let milestones: [Milestone]

    static let empty = MilestonesResponse(tier: .zero, milestones: [])
}

// MARK: - Formatting helpers

/// Formats a cent amount as a localized USD currency string.
func formatCents(_ cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
}

/// A short relative description of a date, e.g. "2 days ago".
func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}
